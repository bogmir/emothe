defmodule Emothe.Export.TeiXml do
  @moduledoc """
  Generates TEI-XML from a play record and its content.
  """

  alias Emothe.PlayContent
  import XmlBuilder

  def generate(play) do
    play = Emothe.Repo.preload(play, [:editors, :sources, :editorial_notes])
    characters = PlayContent.list_characters(play.id)
    divisions = PlayContent.load_play_content(play.id)

    tei =
      element(
        :TEI,
        %{"xml:lang" => play.language || "es", "xmlns" => "http://www.tei-c.org/ns/1.0"},
        [
          build_header(play),
          build_text(play, characters, divisions)
        ]
      )

    XmlBuilder.generate(tei, format: :indent, encoding: nil)
  end

  # --- Header ---

  defp build_header(play) do
    element(:teiHeader, [
      build_file_desc(play),
      build_encoding_desc(play)
    ])
  end

  defp build_file_desc(play) do
    element(:fileDesc, [
      build_title_stmt(play),
      build_edition_stmt(play),
      build_extent(play),
      build_publication_stmt(play),
      build_source_desc(play)
    ])
  end

  defp build_title_stmt(play) do
    titles = [
      element(:title, play.title)
    ]

    titles =
      if play.title_sort,
        do: titles ++ [element(:title, %{key: "orden"}, play.title_sort)],
        else: titles

    titles =
      titles ++ [element(:title, %{key: "archivo"}, play.code)]

    authors =
      if play.author_name do
        author_attrs = if play.author_attribution, do: %{ana: play.author_attribution}, else: %{}

        [element(:author, author_attrs, play.author_name)] ++
          if play.author_sort do
            [element(:author, %{key: "orden"}, play.author_sort)]
          else
            []
          end
      else
        []
      end

    principal =
      play.editors
      |> Enum.filter(&(&1.role == "principal"))
      |> Enum.map(fn e -> element(:principal, e.person_name) end)

    element(:titleStmt, titles ++ authors ++ principal)
  end

  defp build_edition_stmt(play) do
    editors =
      play.editors
      |> Enum.filter(&(&1.role in ["editor", "digital_editor", "reviewer"]))
      |> Enum.map(fn e ->
        resp_label =
          case e.role do
            "editor" -> "Edición"
            "reviewer" -> "Revisión"
            _ -> "Edición digital"
          end

        children = [
          element(:resp, resp_label),
          element(:persName, e.person_name)
        ]

        children =
          if e.organization,
            do: children ++ [element(:orgName, e.organization)],
            else: children

        element(:respStmt, children)
      end)

    element(:editionStmt, [
      element(:edition, "Edición electrónica de '#{play.title}'")
      | editors
    ])
  end

  defp build_extent(play) do
    if play.verse_count do
      element(:extent, %{ana: "verso"}, "#{play.verse_count} versos")
    else
      element(:extent, "")
    end
  end

  defp build_publication_stmt(play) do
    children = [
      element(:idno, %{type: "code"}, play.code),
      element(:pubPlace, play.pub_place || ""),
      element(:date, play.publication_date || "")
    ]

    children =
      if play.publisher,
        do: [element(:publisher, element(:orgName, play.publisher)) | children],
        else: children

    children =
      if play.availability_note,
        do: children ++ [element(:availability, element(:p, play.availability_note))],
        else: children

    element(:publicationStmt, children)
  end

  defp build_source_desc(play) do
    bibls =
      Enum.map(play.sources, fn source ->
        children =
          [
            if(source.title, do: element(:title, source.title)),
            if(source.author, do: element(:author, source.author)),
            if(source.editor, do: element(:editor, source.editor)),
            if(source.note, do: element(:note, source.note))
          ]
          |> Enum.reject(&is_nil/1)

        element(:bibl, children)
      end)

    element(:sourceDesc, if(bibls == [], do: [element(:p, "")], else: bibls))
  end

  defp build_encoding_desc(play) do
    children = []

    children =
      if play.project_description,
        do: children ++ [element(:projectDesc, element(:p, play.project_description))],
        else: children

    children =
      if play.editorial_declaration,
        do: children ++ [element(:editorialDecl, element(:p, play.editorial_declaration))],
        else: children

    element(:encodingDesc, if(children == [], do: [element(:p, "")], else: children))
  end

  # --- Text ---

  defp build_text(play, characters, divisions) do
    front_divisions =
      Enum.filter(divisions, fn d -> d.type in ["elenco", "front", "dedicatoria"] end)

    body_divisions = Enum.filter(divisions, fn d -> d.type == "acto" end)

    element(:text, [
      build_front(play, characters, front_divisions),
      build_body(body_divisions),
      element(:back)
    ])
  end

  defp build_front(play, characters, _front_divisions) do
    title_page =
      element(
        :titlePage,
        [
          element(:docTitle, [element(:titlePart, [element(:title, play.title)])]),
          if(play.author_name, do: element(:docAuthor, play.author_name), else: nil)
        ]
        |> Enum.reject(&is_nil/1)
      )

    # Editorial notes as front divs
    note_divs =
      play.editorial_notes
      |> Enum.map(fn note ->
        children = []
        children = if note.heading, do: [element(:head, note.heading) | children], else: children

        paragraphs =
          note.content
          |> String.split("\n\n")
          |> Enum.map(&element(:p, &1))

        element(:div, %{type: note.section_type}, children ++ paragraphs)
      end)

    # Cast list
    cast_list =
      if characters != [] do
        cast_items =
          Enum.map(characters, fn char ->
            role_attrs = %{"xml:id" => char.xml_id}

            children = [element(:role, role_attrs, char.name)]

            children =
              if char.description,
                do: children ++ [element(:roleDesc, char.description)],
                else: children

            item_attrs = if char.is_hidden, do: %{ana: "oculto"}, else: %{}
            element(:castItem, item_attrs, children)
          end)

        [element(:div, %{type: "elenco"}, [element(:castList, cast_items)])]
      else
        []
      end

    element(:front, [title_page] ++ note_divs ++ cast_list)
  end

  defp build_body(act_divisions) do
    acts =
      Enum.map(act_divisions, fn act ->
        attrs = %{type: "acto"}
        attrs = if act.number, do: Map.put(attrs, :n, to_string(act.number)), else: attrs

        children = if act.title, do: [element(:head, act.title)], else: []

        # Add elements from the act
        elements = Map.get(act, :loaded_elements, [])
        element_xml = Enum.map(elements, &build_element/1)

        # Add scene sub-divisions
        scene_children =
          Map.get(act, :children, [])
          |> Enum.flat_map(fn scene ->
            scene_attrs = %{type: "escena"}

            scene_attrs =
              if scene.number,
                do: Map.put(scene_attrs, :n, to_string(scene.number)),
                else: scene_attrs

            scene_head = if scene.title, do: [element(:head, scene.title)], else: []
            scene_elements = Map.get(scene, :loaded_elements, []) |> Enum.map(&build_element/1)

            [element(:div2, scene_attrs, scene_head ++ scene_elements)]
          end)

        element(:div1, attrs, children ++ element_xml ++ scene_children)
      end)

    element(:body, acts)
  end

  defp build_element(%{type: "speech"} = el) do
    children = []

    children =
      if el.speaker_label, do: [element(:speaker, el.speaker_label) | children], else: children

    child_elements =
      Map.get(el, :children, [])
      |> Enum.map(&build_element/1)

    attrs = if el.character, do: %{who: "##{el.character.xml_id}"}, else: %{}
    element(:sp, attrs, children ++ child_elements)
  end

  defp build_element(%{type: "line_group"} = el) do
    attrs = %{}
    attrs = if el.verse_type, do: Map.put(attrs, :type, el.verse_type), else: attrs
    attrs = if el.part, do: Map.put(attrs, :part, el.part), else: attrs

    lines = Map.get(el, :children, []) |> Enum.map(&build_element/1)
    element(:lg, attrs, lines)
  end

  defp build_element(%{type: "verse_line"} = el) do
    attrs = %{}
    attrs = if el.line_id, do: Map.put(attrs, "xml:id", el.line_id), else: attrs

    attrs =
      if el.line_number,
        do: Map.put(attrs, :n, String.pad_leading(to_string(el.line_number), 4, "0")),
        else: attrs

    attrs = if el.part, do: Map.put(attrs, :part, el.part), else: attrs
    attrs = if el.rend, do: Map.put(attrs, :rend, el.rend), else: attrs

    element(:l, attrs, el.content || "")
  end

  defp build_element(%{type: "stage_direction"} = el) do
    element(:stage, el.content || "")
  end

  defp build_element(%{type: "prose"} = el) do
    element(:p, el.content || "")
  end

  defp build_element(_), do: nil
end
