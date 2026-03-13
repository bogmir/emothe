defmodule Emothe.Export.CompareHtml do
  @moduledoc """
  Generates a standalone HTML document with multiple plays side-by-side
  for comparison. Self-contained with embedded CSS and JS for synchronized
  scrolling between panels. No external dependencies.
  """

  alias Emothe.PlayContent

  def generate(plays) when is_list(plays) do
    panels =
      Enum.map(plays, fn play ->
        play = Emothe.Repo.preload(play, [:editors, :sources])
        characters = PlayContent.list_characters(play.id)
        divisions = PlayContent.load_play_content(play.id)
        {play, characters, divisions}
      end)

    """
    <!DOCTYPE html>
    <html lang="es">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>#{comparison_title(panels)} — EMOTHE</title>
      <style>
    #{css()}
    #{comparison_css(length(panels))}
      </style>
    </head>
    <body>
      <div id="sync-scroll" class="comparison-grid">
    #{render_panels(panels)}
      </div>
    #{sync_scroll_js()}
    </body>
    </html>
    """
  end

  defp comparison_title(panels) do
    panels
    |> Enum.map(fn {play, _, _} -> escape(play.code || play.title) end)
    |> Enum.join(" vs ")
  end

  defp css do
    ~s"""
        * { margin: 0; padding: 0; box-sizing: border-box; }

        html, body {
          height: 100%;
          overflow: hidden;
        }

        body {
          background-color: #faf5ee;
          font-family: Verdana, Geneva, sans-serif;
          line-height: 150%;
          color: #333;
          font-size: 13px;
        }

        /* Panel header */
        .panel-header {
          position: sticky;
          top: 0;
          z-index: 10;
          background: #faf5ee;
          border-bottom: 1px solid #ddd;
          padding: 0.75rem 1rem;
          text-align: center;
          font-family: Georgia, "Times New Roman", Times, serif;
          flex-shrink: 0;
        }

        .panel-header .author {
          font-size: 12px;
          color: #7E7B6A;
        }

        .panel-header .title {
          font-size: 14px;
          font-weight: bold;
          text-transform: uppercase;
        }

        .panel-header .code {
          font-size: 11px;
          color: rgba(51, 51, 51, 0.4);
        }

        .panel-body {
          padding: 0.75rem;
          overflow-y: auto;
          flex: 1;
        }

        /* Cast list */
        .cast-list {
          max-width: 100%;
          margin: 0 auto 1rem;
        }

        .cast-item {
          display: flex;
          align-items: baseline;
          gap: 0.5rem;
          padding: 0.125rem 0;
          margin-left: 0.5rem;
        }

        .cast-name {
          font-weight: bold;
          font-size: x-small;
          text-transform: uppercase;
          flex-shrink: 0;
        }

        .cast-desc { font-size: 12px; color: rgba(51, 51, 51, 0.55); }

        /* Division headings */
        .act-heading {
          font-weight: bold;
          text-align: center;
          font-size: 1rem;
          margin: 1rem 0;
        }

        .scene-heading {
          font-weight: bold;
          text-align: center;
          font-size: 0.8rem;
          margin: 0.75rem 0;
        }

        /* Speech blocks */
        .speech {
          margin-top: 0.375rem;
          margin-bottom: 0.75rem;
        }

        .speech.aside {
          padding-left: 1.5rem;
          border-left: 2px solid #ccc;
        }

        .speaker {
          font-weight: bold;
          font-size: x-small;
          text-transform: uppercase;
          color: #333;
          margin-bottom: 0.125rem;
        }

        /* Verse lines */
        .verse-line {
          display: flex;
          align-items: baseline;
          gap: 0.25rem;
          margin-left: 0.5rem;
        }

        .verse-line .content { flex: 1; }
        .verse-line .content.indent { padding-left: 1.5rem; }
        .verse-line .content.part-m { padding-left: 40px; }
        .verse-line .content.part-f { padding-left: 80px; }

        .line-number {
          width: 1.5rem;
          text-align: left;
          flex-shrink: 0;
          font-size: x-small;
          color: #999;
          font-variant-numeric: tabular-nums;
          user-select: none;
        }

        /* Stage directions */
        .stage-direction {
          text-align: center;
          font-style: italic;
          color: #555;
          margin: 0.5rem 1rem;
          font-size: 12px;
        }

        /* Prose */
        .prose-block {
          margin-left: 0.5rem;
          margin-bottom: 0.375rem;
          text-align: justify;
        }

        .division { margin-bottom: 1.5rem; }
        .child-division { margin-bottom: 1rem; }
    """
  end

  defp comparison_css(panel_count) do
    cols = min(panel_count, 4)

    font_size =
      case cols do
        1 -> "14px"
        2 -> "13px"
        3 -> "12px"
        _ -> "11px"
      end

    """
        .comparison-grid {
          display: grid;
          grid-template-columns: repeat(#{cols}, 1fr);
          gap: 0;
          height: 100vh;
        }

        .panel {
          border-right: 1px solid #ddd;
          min-width: 0;
          font-size: #{font_size};
          display: flex;
          flex-direction: column;
          height: 100vh;
          overflow: hidden;
        }

        .panel:last-child {
          border-right: none;
        }

        @media print {
          html, body { height: auto; overflow: auto; }
          body { background: white; font-size: #{font_size}; }
          .comparison-grid { height: auto; gap: 0; }
          .panel { height: auto; overflow: visible; border-right-color: #ccc; }
          .panel-header { position: static; background: white; }
          .panel-body { overflow: visible; }
          .act-heading { page-break-before: always; }
          .speech { break-inside: avoid; }
          .verse-line { break-inside: avoid; }
        }
    """
  end

  defp sync_scroll_js do
    ~s"""
    <script>
    document.addEventListener("DOMContentLoaded", function() {
      var container = document.getElementById("sync-scroll");
      var panels = Array.from(container.querySelectorAll("[data-panel]"));
      if (panels.length < 2) return;

      var activePanel = null;

      function findTopAnchor(panel) {
        var anchors = panel.querySelectorAll("[data-speech-key], [data-sync-div]");
        var panelTop = panel.getBoundingClientRect().top;
        var best = null, bestDist = Infinity, bestAttr = null;
        for (var i = 0; i < anchors.length; i++) {
          var el = anchors[i];
          var top = el.getBoundingClientRect().top - panelTop;
          if (top >= -50 && top < bestDist) {
            bestDist = top;
            best = el;
            bestAttr = el.hasAttribute("data-speech-key") ? "data-speech-key" : "data-sync-div";
          }
        }
        return best ? { el: best, attr: bestAttr, key: best.getAttribute(bestAttr) } : null;
      }

      function syncTo(source, target) {
        var anchor = findTopAnchor(source);
        if (!anchor) return;
        var match = target.querySelector("[" + anchor.attr + '="' + anchor.key + '"]');
        if (match) {
          var sourceOffset = anchor.el.getBoundingClientRect().top - source.getBoundingClientRect().top;
          var matchOffset = match.getBoundingClientRect().top - target.getBoundingClientRect().top;
          target.scrollTop += (matchOffset - sourceOffset);
        }
      }

      var rafId = null;
      function throttledSync(source, targets) {
        if (rafId) return;
        rafId = requestAnimationFrame(function() {
          rafId = null;
          targets.forEach(function(t) { syncTo(source, t); });
        });
      }

      panels.forEach(function(panel, i) {
        panel.addEventListener("pointerenter", function() { activePanel = i; });
        panel.addEventListener("pointerleave", function() { if (activePanel === i) activePanel = null; });
        panel.addEventListener("scroll", function() {
          if (activePanel === i) {
            var others = panels.filter(function(_, j) { return j !== i; });
            throttledSync(panel, others);
          }
        }, { passive: true });
      });

      // Initial alignment
      requestAnimationFrame(function() {
        panels.slice(1).forEach(function(t) { syncTo(panels[0], t); });
      });
    });
    </script>
    """
  end

  defp render_panels(panels) do
    panels
    |> Enum.with_index()
    |> Enum.map(fn {{play, characters, divisions}, idx} ->
      """
          <div class="panel">
            <div class="panel-header">
              <p class="author">#{escape(play.author_name || "")}</p>
              <p class="title">#{escape(play.title)}</p>
              <p class="code">#{escape(play.code || "")}</p>
            </div>
            <div class="panel-body" data-panel="panel-#{idx}">
      #{render_divisions(divisions, characters)}
            </div>
          </div>
      """
    end)
    |> Enum.join("\n")
  end

  @act_types ~w(acto act acte jornada)

  defp render_divisions(divisions, characters) do
    Enum.map(divisions, fn div ->
      div_key = div_key(div)
      heading = division_heading(div, div_key)

      cast =
        if div.type == "elenco",
          do: render_inline_cast_list(characters),
          else: ""

      elements = render_elements(Map.get(div, :loaded_elements, []), div_key)

      children =
        Map.get(div, :children, [])
        |> Enum.map(fn child ->
          child_key = "#{div_key}/#{div_key(child)}"
          ch = child_heading(child, child_key)
          ce = render_elements(Map.get(child, :loaded_elements, []), child_key)
          "      <div class=\"child-division\">\n#{ch}#{ce}      </div>"
        end)
        |> Enum.join("\n")

      "    <div class=\"division\">\n#{heading}#{cast}#{elements}#{children}\n    </div>"
    end)
    |> Enum.join("\n")
  end

  defp div_key(div) do
    "#{div.type}-#{div.number || div.position}"
  end

  defp division_heading(%{title: nil}, _key), do: ""
  defp division_heading(%{title: ""}, _key), do: ""

  defp division_heading(%{title: title, type: type}, key) when type in @act_types do
    "      <h2 class=\"act-heading\" data-sync-div=\"#{key}\">#{escape(title)}</h2>\n"
  end

  defp division_heading(%{title: title}, key) do
    "      <h3 class=\"scene-heading\" data-sync-div=\"#{key}\">#{escape(title)}</h3>\n"
  end

  defp child_heading(%{title: nil}, _key), do: ""
  defp child_heading(%{title: ""}, _key), do: ""

  defp child_heading(%{title: title}, key),
    do: "        <h3 class=\"scene-heading\" data-sync-div=\"#{key}\">#{escape(title)}</h3>\n"

  defp render_inline_cast_list(characters) do
    visible = Enum.reject(characters, & &1.is_hidden)
    if visible == [], do: "", else: do_render_inline_cast_list(visible)
  end

  defp do_render_inline_cast_list(characters) do
    items =
      Enum.map(characters, fn char ->
        desc =
          if char.description,
            do: " <span class=\"cast-desc\">#{escape(char.description)}</span>",
            else: ""

        "          <div class=\"cast-item\"><span class=\"cast-name\">#{escape(char.name)}</span>#{desc}</div>"
      end)
      |> Enum.join("\n")

    """
          <div class="cast-list">
    #{items}
          </div>
    """
  end

  defp render_elements(elements, div_key) do
    {rendered, _ordinal} =
      Enum.map_reduce(elements, 0, fn el, ordinal ->
        if el.type == "speech" do
          speech_key = "#{div_key}/speech-#{ordinal}"
          {render_element(el, speech_key), ordinal + 1}
        else
          {render_element(el, nil), ordinal}
        end
      end)

    Enum.join(rendered)
  end

  defp render_element(%{type: "speech"} = el, speech_key) do
    aside_class = if el.is_aside, do: " aside", else: ""
    key_attr = if speech_key, do: " data-speech-key=\"#{speech_key}\"", else: ""

    speaker =
      if el.speaker_label,
        do: "        <div class=\"speaker\">#{escape(el.speaker_label)}</div>\n",
        else: ""

    children = Map.get(el, :children, []) |> Enum.map(&render_element(&1, nil)) |> Enum.join()
    "      <div class=\"speech#{aside_class}\"#{key_attr}>\n#{speaker}#{children}      </div>\n"
  end

  defp render_element(%{type: "line_group"} = el, _key) do
    Map.get(el, :children, []) |> Enum.map(&render_element(&1, nil)) |> Enum.join()
  end

  defp render_element(%{type: "verse_line"} = el, _key) do
    content_class =
      cond do
        el.rend == "indent" -> "content indent"
        el.part == "F" -> "content part-f"
        el.part == "M" -> "content part-m"
        true -> "content"
      end

    line_num =
      if el.line_number,
        do: "<span class=\"line-number\">#{el.line_number}</span>",
        else: "<span class=\"line-number\"></span>"

    "        <div class=\"verse-line\"><span class=\"#{content_class}\">#{escape(el.content || "")}</span>#{line_num}</div>\n"
  end

  defp render_element(%{type: "stage_direction"} = el, _key) do
    "        <div class=\"stage-direction\">(#{escape(el.content || "")})</div>\n"
  end

  defp render_element(%{type: "prose"} = el, _key) do
    "        <div class=\"prose-block\">#{escape(el.content || "")}</div>\n"
  end

  defp render_element(_, _key), do: ""

  defp escape(nil), do: ""

  defp escape(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
