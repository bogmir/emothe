// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/emothe"
import topbar from "../vendor/topbar"

// ScrollSpy hook: highlights the sidebar link matching the currently visible section
const ScrollSpy = {
  mounted() { this._setup() },
  updated() { this._setup() },
  destroyed() { if (this._obs) this._obs.disconnect() },
  _setup() {
    if (this._obs) this._obs.disconnect()

    const links = this.el.querySelectorAll("a[href^='#']")
    const ids = Array.from(links).map(a => a.getAttribute("href").slice(1))
    const targets = ids.map(id => document.getElementById(id)).filter(Boolean)
    if (!targets.length) return

    // Track which sections are currently intersecting
    const visible = new Map()

    this._obs = new IntersectionObserver((entries) => {
      for (const e of entries) {
        if (e.isIntersecting) {
          visible.set(e.target.id, e.boundingClientRect.top)
        } else {
          visible.delete(e.target.id)
        }
      }

      // Pick the topmost visible section
      let activeId = null
      let minTop = Infinity
      for (const [id, top] of visible) {
        if (top < minTop) { minTop = top; activeId = id }
      }

      links.forEach(link => {
        const isActive = link.getAttribute("href").slice(1) === activeId
        link.classList.toggle("scroll-spy-active", isActive)
      })
    }, { rootMargin: "-5% 0px -65% 0px", threshold: 0 })

    targets.forEach(t => this._obs.observe(t))
  }
}

// SyncScroll hook: synchronizes scroll position between two comparison panels.
// Tracks which panel the user is hovering over to avoid feedback loops.
const SyncScroll = {
  mounted() { this._setup() },
  updated() { this._setup() },
  destroyed() { this._cleanup() },
  _cleanup() {
    if (this._leftHandler) this._left?.removeEventListener("scroll", this._leftHandler)
    if (this._rightHandler) this._right?.removeEventListener("scroll", this._rightHandler)
    if (this._left) {
      this._left.removeEventListener("pointerenter", this._leftEnter)
      this._left.removeEventListener("pointerleave", this._leftLeave)
    }
    if (this._right) {
      this._right.removeEventListener("pointerenter", this._rightEnter)
      this._right.removeEventListener("pointerleave", this._rightLeave)
    }
  },
  _setup() {
    this._cleanup()

    this._left = this.el.querySelector('[data-panel="left"]')
    this._right = this.el.querySelector('[data-panel="right"]')
    if (!this._left || !this._right) return

    // Track which panel the user is actively scrolling
    this._activePanel = null

    this._leftEnter = () => { this._activePanel = "left" }
    this._leftLeave = () => { if (this._activePanel === "left") this._activePanel = null }
    this._rightEnter = () => { this._activePanel = "right" }
    this._rightLeave = () => { if (this._activePanel === "right") this._activePanel = null }

    this._left.addEventListener("pointerenter", this._leftEnter)
    this._left.addEventListener("pointerleave", this._leftLeave)
    this._right.addEventListener("pointerenter", this._rightEnter)
    this._right.addEventListener("pointerleave", this._rightLeave)

    // Find the topmost visible anchor (speech or division heading) in a panel
    const findTopAnchor = (panel) => {
      const anchors = panel.querySelectorAll("[data-speech-key], [data-sync-div]")
      const panelTop = panel.getBoundingClientRect().top
      let best = null
      let bestDist = Infinity
      let bestAttr = null
      for (const el of anchors) {
        const top = el.getBoundingClientRect().top - panelTop
        if (top >= -50 && top < bestDist) {
          bestDist = top
          best = el
          bestAttr = el.hasAttribute("data-speech-key") ? "data-speech-key" : "data-sync-div"
        }
      }
      return best ? { el: best, attr: bestAttr, key: best.getAttribute(bestAttr) } : null
    }

    const syncTo = (source, target) => {
      const anchor = findTopAnchor(source)
      if (!anchor) return
      const match = target.querySelector(`[${anchor.attr}="${anchor.key}"]`)
      if (match) {
        // How far the anchor is from the top of the source panel
        const sourceOffset = anchor.el.getBoundingClientRect().top - source.getBoundingClientRect().top
        // How far the match currently is from the top of the target panel
        const matchOffset = match.getBoundingClientRect().top - target.getBoundingClientRect().top
        // Scroll target so the match sits at the same offset as the anchor
        target.scrollTop += (matchOffset - sourceOffset)
      }
    }

    // Throttle sync to one rAF per scroll burst
    let rafId = null
    const throttledSync = (source, target) => {
      if (rafId) return
      rafId = requestAnimationFrame(() => {
        rafId = null
        syncTo(source, target)
      })
    }

    this._leftHandler = () => {
      if (this._activePanel === "left") throttledSync(this._left, this._right)
    }
    this._rightHandler = () => {
      if (this._activePanel === "right") throttledSync(this._right, this._left)
    }

    this._left.addEventListener("scroll", this._leftHandler, { passive: true })
    this._right.addEventListener("scroll", this._rightHandler, { passive: true })

    // Initial alignment: sync right panel to left after DOM settles
    requestAnimationFrame(() => syncTo(this._left, this._right))
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ScrollSpy, SyncScroll},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

