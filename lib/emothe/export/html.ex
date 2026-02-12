defmodule Emothe.Export.Html do
  @moduledoc """
  Generates a standalone HTML document for a play.
  """

  alias Emothe.PlayContent

  def generate(play) do
    play = Emothe.Repo.preload(play, [:editors, :sources, :editorial_notes])
    characters = PlayContent.list_characters(play.id)
    divisions = PlayContent.load_play_content(play.id)

    """
    <!DOCTYPE html>
    <html lang="#{play.language || "es"}">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>#{escape(play.title)} — #{escape(play.author_name || "")}</title>
      <style>
        body { font-family: Georgia, 'Times New Roman', serif; max-width: 800px; margin: 0 auto; padding: 2rem; color: #333; line-height: 1.6; }
        h1 { text-align: center; font-size: 2rem; margin-bottom: 0.5rem; }
        .author { text-align: center; font-size: 1.2rem; color: #666; margin-bottom: 2rem; }
        .metadata { background: #f9f6f0; border: 1px solid #e5ddd0; padding: 1rem; border-radius: 4px; margin-bottom: 2rem; font-size: 0.9rem; }
        .act-heading { text-align: center; font-size: 1.5rem; font-weight: bold; margin: 2rem 0 1rem; }
        .scene-heading { text-align: center; font-size: 1.1rem; font-weight: bold; color: #555; margin: 1.5rem 0 1rem; }
        .speech { margin-bottom: 1rem; }
        .speaker { font-weight: bold; text-transform: uppercase; font-size: 0.85rem; letter-spacing: 0.05em; color: #555; }
        .verse-line { display: flex; gap: 0.5rem; }
        .line-number { color: #aaa; font-size: 0.8rem; width: 2.5rem; text-align: right; flex-shrink: 0; user-select: none; }
        .stage-direction { text-align: center; font-style: italic; color: #777; margin: 0.75rem 2rem; }
        .cast-list { columns: 2; margin-bottom: 2rem; }
        .cast-item { break-inside: avoid; margin-bottom: 0.25rem; }
        .cast-name { font-weight: bold; }
        .cast-desc { color: #666; font-style: italic; }
        .indent { padding-left: 3rem; }
        .part-f { padding-left: 4rem; }
        .part-m { padding-left: 2rem; }
        .editorial-note { background: #fffbeb; border: 1px solid #fde68a; padding: 1rem; border-radius: 4px; margin-bottom: 1.5rem; }
      </style>
    </head>
    <body>
      <h1>#{escape(play.title)}</h1>
      <p class="author">#{escape(play.author_name || "")}</p>

      #{render_metadata(play)}
      #{render_editorial_notes(play.editorial_notes)}
      #{render_cast_list(characters)}
      #{render_divisions(divisions)}
    </body>
    </html>
    """
  end

  defp render_metadata(play) do
    parts = []

    parts =
      if play.pub_place,
        do: ["<strong>Place:</strong> #{escape(play.pub_place)}" | parts],
        else: parts

    parts =
      if play.publication_date,
        do: ["<strong>Date:</strong> #{escape(play.publication_date)}" | parts],
        else: parts

    parts =
      if play.verse_count,
        do: ["<strong>Verses:</strong> #{play.verse_count}" | parts],
        else: parts

    sources =
      play.sources
      |> Enum.map(fn s -> if s.note, do: "<p><em>#{escape(s.note)}</em></p>", else: "" end)
      |> Enum.join()

    if parts != [] or sources != "" do
      "<div class=\"metadata\">#{Enum.join(parts, " | ")}#{sources}</div>"
    else
      ""
    end
  end

  defp render_editorial_notes(notes) do
    notes
    |> Enum.map(fn note ->
      heading = if note.heading, do: "<h3>#{escape(note.heading)}</h3>", else: ""

      content =
        note.content |> String.split("\n\n") |> Enum.map(&"<p>#{escape(&1)}</p>") |> Enum.join()

      "<div class=\"editorial-note\">#{heading}#{content}</div>"
    end)
    |> Enum.join()
  end

  defp render_cast_list([]), do: ""

  defp render_cast_list(characters) do
    items =
      characters
      |> Enum.reject(& &1.is_hidden)
      |> Enum.map(fn char ->
        desc =
          if char.description,
            do: " <span class=\"cast-desc\">#{escape(char.description)}</span>",
            else: ""

        "<div class=\"cast-item\"><span class=\"cast-name\">#{escape(char.name)}</span>#{desc}</div>"
      end)
      |> Enum.join()

    "<h2 style=\"text-align:center\">PERSONAJES</h2><div class=\"cast-list\">#{items}</div>"
  end

  defp render_divisions(divisions) do
    Enum.map(divisions, fn div ->
      heading =
        if div.title do
          class = if div.type == "acto", do: "act-heading", else: "scene-heading"
          "<div class=\"#{class}\">#{escape(div.title)}</div>"
        else
          ""
        end

      elements = Map.get(div, :loaded_elements, []) |> Enum.map(&render_element/1) |> Enum.join()

      children =
        Map.get(div, :children, [])
        |> Enum.map(fn child ->
          child_heading =
            if child.title,
              do: "<div class=\"scene-heading\">#{escape(child.title)}</div>",
              else: ""

          child_elements =
            Map.get(child, :loaded_elements, []) |> Enum.map(&render_element/1) |> Enum.join()

          child_heading <> child_elements
        end)
        |> Enum.join()

      heading <> elements <> children
    end)
    |> Enum.join()
  end

  defp render_element(%{type: "speech"} = el) do
    speaker =
      if el.speaker_label,
        do: "<div class=\"speaker\">#{escape(el.speaker_label)}</div>",
        else: ""

    children = Map.get(el, :children, []) |> Enum.map(&render_element/1) |> Enum.join()
    "<div class=\"speech\">#{speaker}#{children}</div>"
  end

  defp render_element(%{type: "line_group"} = el) do
    Map.get(el, :children, []) |> Enum.map(&render_element/1) |> Enum.join()
  end

  defp render_element(%{type: "verse_line"} = el) do
    line_num =
      if el.line_number && rem(el.line_number, 5) == 0,
        do: "<span class=\"line-number\">#{el.line_number}</span>",
        else: "<span class=\"line-number\"></span>"

    css_class =
      cond do
        el.rend == "indent" -> " indent"
        el.part == "F" -> " part-f"
        el.part == "M" -> " part-m"
        true -> ""
      end

    "<div class=\"verse-line\">#{line_num}<span class=\"#{css_class}\">#{escape(el.content || "")}</span></div>"
  end

  defp render_element(%{type: "stage_direction"} = el) do
    "<div class=\"stage-direction\">(#{escape(el.content || "")})</div>"
  end

  defp render_element(%{type: "prose"} = el) do
    "<p>#{escape(el.content || "")}</p>"
  end

  defp render_element(_), do: ""

  defp escape(nil), do: ""

  defp escape(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
