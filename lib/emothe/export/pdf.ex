defmodule Emothe.Export.Pdf do
  @moduledoc """
  Generates PDF from a play using Typst.
  Requires Typst CLI to be installed on the system.
  """

  alias Emothe.PlayContent

  def generate(play) do
    play = Emothe.Repo.preload(play, [:editors, :sources, :editorial_notes])
    characters = PlayContent.list_characters(play.id)
    divisions = PlayContent.load_play_content(play.id)

    typst_source = build_typst(play, characters, divisions)

    # Write to temp file, compile with Typst, read PDF
    tmp_dir = System.tmp_dir!()
    source_path = Path.join(tmp_dir, "#{play.code}.typ")
    output_path = Path.join(tmp_dir, "#{play.code}.pdf")

    File.write!(source_path, typst_source)

    case System.cmd("typst", ["compile", source_path, output_path], stderr_to_stdout: true) do
      {_output, 0} ->
        pdf = File.read!(output_path)
        File.rm(source_path)
        File.rm(output_path)
        {:ok, pdf}

      {output, _code} ->
        File.rm(source_path)
        {:error, "Typst compilation failed: #{output}"}
    end
  end

  defp build_typst(play, characters, divisions) do
    """
    #set document(title: "#{typst_escape(play.title)}", author: "#{typst_escape(play.author_name || "")}")
    #set page(margin: (top: 2.5cm, bottom: 2.5cm, left: 3cm, right: 3cm))
    #set text(font: "New Computer Modern", size: 11pt, lang: "#{play.language || "es"}")
    #set par(justify: true)

    #align(center)[
      #text(size: 24pt, weight: "bold")[#{typst_escape(play.title)}]

      #v(0.5cm)
      #text(size: 14pt, fill: rgb("#555"))[#{typst_escape(play.author_name || "")}]
      #v(1cm)
    ]

    #{render_sources_typst(play.sources)}
    #{render_cast_typst(characters)}
    #{render_divisions_typst(divisions)}
    """
  end

  defp render_sources_typst(sources) do
    sources
    |> Enum.map(fn s ->
      if s.note, do: "_#{typst_escape(s.note)}_\n\n", else: ""
    end)
    |> Enum.join()
  end

  defp render_cast_typst(characters) do
    visible = Enum.reject(characters, & &1.is_hidden)

    if visible == [] do
      ""
    else
      header = "#align(center)[#text(size: 14pt, weight: \"bold\")[PERSONAJES]]\n\n"

      items =
        Enum.map(visible, fn char ->
          desc = if char.description, do: " — _#{typst_escape(char.description)}_", else: ""
          "- *#{typst_escape(char.name)}*#{desc}"
        end)
        |> Enum.join("\n")

      header <> items <> "\n\n#pagebreak()\n\n"
    end
  end

  defp render_divisions_typst(divisions) do
    Enum.map(divisions, fn div ->
      heading =
        if div.title && div.type == "acto" do
          "\n#align(center)[#text(size: 16pt, weight: \"bold\")[#{typst_escape(div.title)}]]\n\n"
        else
          if div.title do
            "\n#align(center)[#text(size: 13pt, weight: \"bold\")[#{typst_escape(div.title)}]]\n\n"
          else
            ""
          end
        end

      elements =
        Map.get(div, :loaded_elements, []) |> Enum.map(&render_element_typst/1) |> Enum.join()

      children =
        Map.get(div, :children, [])
        |> Enum.map(fn child ->
          ch =
            if child.title,
              do:
                "\n#align(center)[#text(size: 13pt, weight: \"bold\")[#{typst_escape(child.title)}]]\n\n",
              else: ""

          ce =
            Map.get(child, :loaded_elements, [])
            |> Enum.map(&render_element_typst/1)
            |> Enum.join()

          ch <> ce
        end)
        |> Enum.join()

      heading <> elements <> children
    end)
    |> Enum.join()
  end

  defp render_element_typst(%{type: "speech"} = el) do
    speaker =
      if el.speaker_label,
        do: "#text(weight: \"bold\", size: 9pt)[#upper[#{typst_escape(el.speaker_label)}]]\n",
        else: ""

    children = Map.get(el, :children, []) |> Enum.map(&render_element_typst/1) |> Enum.join()
    speaker <> children <> "\n"
  end

  defp render_element_typst(%{type: "line_group"} = el) do
    Map.get(el, :children, []) |> Enum.map(&render_element_typst/1) |> Enum.join()
  end

  defp render_element_typst(%{type: "verse_line"} = el) do
    content = typst_escape(el.content || "")

    indent =
      cond do
        el.rend == "indent" -> "#h(2em)"
        el.part == "F" -> "#h(3em)"
        el.part == "M" -> "#h(1.5em)"
        true -> ""
      end

    "#{indent}#{content} \\\n"
  end

  defp render_element_typst(%{type: "stage_direction"} = el) do
    "\n#align(center)[#emph[(#{typst_escape(el.content || "")})]]\n\n"
  end

  defp render_element_typst(%{type: "prose"} = el) do
    "#{typst_escape(el.content || "")}\n\n"
  end

  defp render_element_typst(_), do: ""

  defp typst_escape(nil), do: ""

  defp typst_escape(text) when is_binary(text) do
    text
    |> String.replace("\\", "\\\\")
    |> String.replace("#", "\\#")
    |> String.replace("*", "\\*")
    |> String.replace("_", "\\_")
    |> String.replace("[", "\\[")
    |> String.replace("]", "\\]")
    |> String.replace("\"", "\\\"")
  end
end
