defmodule Emothe.Export.TeiXml do
  @moduledoc """
  Generates TEI-XML from a play record and its content.
  """

  alias Emothe.PlayContent
  import XmlBuilder

  @body_types ~w(acto jornada prologo argumento act acte play prologue epilogue)

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

    "<?xml version=\"1.0\" ?>\n" <>
      XmlBuilder.generate(tei, format: :indent, encoding: nil)
  end

  # --- Header ---

  defp build_header(play) do
    element(:teiHeader, [
      build_file_desc(play),
      build_encoding_desc(play),
      build_profile_desc(play)
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
    # Main title — use type="traduccion" if this is a translation
    main_title_attrs =
      if play.relationship_type == "traduccion", do: %{type: "traduccion"}, else: %{}

    titles = [element(:title, main_title_attrs, play.title)]

    titles =
      if play.original_title,
        do: [element(:title, %{type: "original"}, play.original_title) | titles],
        else: titles

    titles =
      if play.edition_title,
        do: titles ++ [element(:title, %{type: "edicion"}, play.edition_title)],
        else: titles

    titles =
      if play.title_sort,
        do: titles ++ [element(:title, %{key: "orden"}, play.title_sort)],
        else: titles

    titles = titles ++ [element(:title, %{key: "archivo"}, play.code)]

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

    # Translators as <editor role="translator"><persName>...
    translators =
      play.editors
      |> Enum.filter(&(&1.role == "translator"))
      |> Enum.map(fn e ->
        element(:editor, %{role: "translator"}, [element(:persName, e.person_name)])
      end)

    # respStmt for digital editors in titleStmt (from titleStmt import)
    resp_stmts =
      play.editors
      |> Enum.filter(
        &(&1.role in ["digital_editor", "editor", "reviewer"] and &1.position >= 100 and
            &1.position < 200)
      )
      |> Enum.map(fn e ->
        resp_label =
          case e.role do
            "editor" -> "Edición"
            "reviewer" -> "Revisión"
            _ -> "Electronic edition"
          end

        children = [element(:resp, resp_label), element(:persName, e.person_name)]

        children =
          if e.organization,
            do: children ++ [element(:orgName, e.organization)],
            else: children

        element(:respStmt, children)
      end)

    principal =
      play.editors
      |> Enum.filter(&(&1.role == "principal"))
      |> Enum.map(fn e -> element(:principal, e.person_name) end)

    sponsor =
      if play.sponsor,
        do: [element(:sponsor, [element(:orgName, play.sponsor)])],
        else: []

    funder =
      if play.funder,
        do: [element(:funder, [element(:orgName, play.funder)])],
        else: []

    element(
      :titleStmt,
      titles ++ authors ++ translators ++ sponsor ++ funder ++ resp_stmts ++ principal
    )
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
    idno_children = [element(:idno, %{type: "code"}, play.code)]

    idno_children =
      if play.emothe_id,
        do: idno_children ++ [element(:idno, %{type: "EMOTHE"}, play.emothe_id)],
        else: idno_children

    children =
      idno_children ++
        [
          element(:pubPlace, play.pub_place || ""),
          element(:date, play.publication_date || "")
        ]

    children =
      if play.publisher,
        do: [element(:publisher, [element(:orgName, play.publisher)]) | children],
        else: children

    children =
      if play.authority,
        do: children ++ [element(:authority, [element(:orgName, play.authority)])],
        else: children

    # Build availability with optional <p> and <licence>
    availability_children =
      []
      |> then(fn acc ->
        if play.availability_note,
          do: acc ++ [element(:p, play.availability_note)],
          else: acc
      end)
      |> then(fn acc ->
        if play.licence_url || play.licence_text do
          licence_attrs = if play.licence_url, do: %{target: play.licence_url}, else: %{}
          acc ++ [element(:licence, licence_attrs, play.licence_text || "")]
        else
          acc
        end
      end)

    children =
      if availability_children != [],
        do: children ++ [element(:availability, availability_children)],
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
            if source.editor do
              attrs = if source.editor_role, do: %{role: source.editor_role}, else: %{}
              element(:editor, attrs, source.editor)
            end,
            if(source.language, do: element(:lang, source.language)),
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
        do: children ++ [element(:projectDesc, [element(:p, play.project_description)])],
        else: children

    children =
      if play.editorial_declaration,
        do: children ++ [element(:editorialDecl, [element(:p, play.editorial_declaration)])],
        else: children

    element(:encodingDesc, if(children == [], do: [element(:p, "")], else: children))
  end

  @language_ident_labels %{
    "es" => {"es-ES", "Español"},
    "en" => {"en-EN", "English"},
    "it" => {"it-IT", "Italiano"},
    "ca" => {"ca-ES", "Català"},
    "fr" => {"fr-FR", "Français"},
    "pt" => {"pt-PT", "Português"}
  }

  defp build_profile_desc(play) do
    {ident, label} = Map.get(@language_ident_labels, play.language || "es", {"es-ES", "Español"})

    element(:profileDesc, [
      element(:langUsage, [
        element(:language, %{ident: ident}, label)
      ])
    ])
  end

  # --- Text ---

  defp build_text(play, characters, divisions) do
    body_divisions = Enum.filter(divisions, fn d -> d.type in @body_types end)

    element(:text, [
      build_front(play, characters),
      build_body(body_divisions),
      element(:back)
    ])
  end

  defp build_front(play, characters) do
    title_page =
      element(
        :titlePage,
        [
          element(:docTitle, [element(:titlePart, [element(:title, play.title)])]),
          if(play.author_name, do: element(:docAuthor, play.author_name), else: nil)
        ]
        |> Enum.reject(&is_nil/1)
      )

    # Editorial notes as front divs with their stored section_type
    note_divs =
      play.editorial_notes
      |> Enum.sort_by(& &1.position)
      |> Enum.map(fn note ->
        head = if note.heading, do: [element(:head, note.heading)], else: []

        paragraphs =
          note.content
          |> String.split("\n\n")
          |> Enum.map(&element(:p, &1))

        element(:div, %{type: note.section_type}, head ++ paragraphs)
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

  defp build_body(body_divisions) do
    divs =
      Enum.map(body_divisions, fn div ->
        attrs = %{type: div.type}
        attrs = if div.number, do: Map.put(attrs, :n, to_string(div.number)), else: attrs

        children = if div.title, do: [element(:head, div.title)], else: []

        # Add elements from the division
        elements = Map.get(div, :loaded_elements, [])
        element_xml = Enum.map(elements, &build_element/1) |> Enum.reject(&is_nil/1)

        # Add sub-divisions (scenes, etc.)
        sub_divs =
          Map.get(div, :children, [])
          |> Enum.map(fn child ->
            child_attrs = %{type: child.type}

            child_attrs =
              if child.number,
                do: Map.put(child_attrs, :n, to_string(child.number)),
                else: child_attrs

            child_head = if child.title, do: [element(:head, child.title)], else: []

            child_elements =
              Map.get(child, :loaded_elements, [])
              |> Enum.map(&build_element/1)
              |> Enum.reject(&is_nil/1)

            element(:div2, child_attrs, child_head ++ child_elements)
          end)

        element(:div1, attrs, children ++ element_xml ++ sub_divs)
      end)

    element(:body, divs)
  end

  defp build_element(%{type: "speech"} = el) do
    children = []

    children =
      if el.speaker_label, do: [element(:speaker, el.speaker_label) | children], else: children

    child_elements =
      Map.get(el, :children, [])
      |> Enum.map(&build_element/1)
      |> Enum.reject(&is_nil/1)

    attrs = if el.character, do: %{who: "##{el.character.xml_id}"}, else: %{}
    element(:sp, attrs, children ++ child_elements)
  end

  defp build_element(%{type: "line_group"} = el) do
    attrs = %{}
    attrs = if el.verse_type, do: Map.put(attrs, :type, el.verse_type), else: attrs
    attrs = if el.part, do: Map.put(attrs, :part, el.part), else: attrs

    lines = Map.get(el, :children, []) |> Enum.map(&build_element/1) |> Enum.reject(&is_nil/1)
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

    content =
      if el.is_aside do
        [element(:seg, %{type: "aside"}, el.content || "")]
      else
        el.content || ""
      end

    element(:l, attrs, content)
  end

  defp build_element(%{type: "stage_direction"} = el) do
    element(:stage, el.content || "")
  end

  defp build_element(%{type: "prose"} = el) do
    content =
      if el.is_aside do
        [element(:seg, %{type: "aside"}, el.content || "")]
      else
        el.content || ""
      end

    element(:p, content)
  end

  defp build_element(_), do: nil
end
