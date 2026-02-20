defmodule Emothe.Import.TeiParser do
  @moduledoc """
  Parses TEI-XML files into database records.

  Handles UTF-16 encoded files (common in the EMOTHE corpus) by converting
  them to UTF-8 before parsing with Saxy.
  """

  alias Emothe.Repo
  alias Emothe.Catalogue
  alias Emothe.Catalogue.Play
  alias Emothe.PlayContent

  require Logger

  @title_small_words MapSet.new([
                       "a",
                       "al",
                       "and",
                       "as",
                       "at",
                       "d",
                       "da",
                       "das",
                       "de",
                       "del",
                       "des",
                       "di",
                       "do",
                       "dos",
                       "e",
                       "el",
                       "en",
                       "et",
                       "i",
                       "la",
                       "las",
                       "le",
                       "les",
                       "los",
                       "of",
                       "or",
                       "the",
                       "to",
                       "y"
                     ])

  @doc """
  Imports a TEI-XML file from the given path into the database.
  Returns {:ok, play} or {:error, reason}.
  """
  def import_file(path) do
    Logger.info("Importing TEI file: #{path}")

    with {:ok, raw} <- File.read(path),
         xml when is_binary(xml) <- normalize_encoding(raw),
         {:ok, tree} <- parse_xml(xml) do
      Repo.transaction(fn ->
        import_tree(tree)
      end)
    else
      {:error, reason} ->
        Logger.error("Import failed for #{path}: #{inspect(reason)}")
        {:error, reason}

      {:incomplete, _, _} = err ->
        Logger.error("Encoding conversion failed for #{path}: #{inspect(err)}")
        {:error, :encoding_error}

      other ->
        Logger.error("Unexpected error importing #{path}: #{inspect(other)}")
        {:error, other}
    end
  end

  # --- Encoding ---

  defp normalize_encoding(raw) do
    # Detect UTF-16 BOM (little-endian or big-endian)
    case raw do
      <<0xFF, 0xFE, rest::binary>> ->
        :unicode.characters_to_binary(rest, {:utf16, :little})

      <<0xFE, 0xFF, rest::binary>> ->
        :unicode.characters_to_binary(rest, {:utf16, :big})

      # Check for null bytes pattern typical of UTF-16LE without BOM
      <<first, 0x00, _rest::binary>> when first != 0x00 ->
        :unicode.characters_to_binary(raw, {:utf16, :little})

      # UTF-8 BOM
      <<0xEF, 0xBB, 0xBF, rest::binary>> ->
        rest

      _ ->
        raw
    end
  end

  # --- XML Parsing ---

  defp parse_xml(xml) do
    # Strip XML declaration and stylesheet processing instructions
    xml = String.replace(xml, ~r/<\?xml[^?]*\?>/, "")
    xml = String.replace(xml, ~r/<\?xml-stylesheet[^?]*\?>/, "")
    xml = String.trim(xml)

    case Saxy.SimpleForm.parse_string(xml) do
      {:ok, tree} -> {:ok, tree}
      {:error, reason} -> {:error, {:xml_parse_error, reason}}
    end
  end

  # --- Import Logic ---

  defp import_tree({_name, _attrs, children} = _tei) do
    header = find_child(children, "teiHeader")
    text = find_child(children, "text")

    play = import_header(header)

    if text do
      import_text(text, play)
    end

    # Recompute verse_count from actual verse_line elements (the TEI header
    # <extent> value is often inaccurate or includes non-verse lines)
    Emothe.Catalogue.update_verse_count(play.id)

    play
  end

  # --- Header ---

  defp import_header({_name, _attrs, children}) do
    file_desc = find_child(children, "fileDesc")
    encoding_desc = find_child(children, "encodingDesc")

    play_attrs = extract_play_attrs(file_desc, encoding_desc)

    play =
      case Repo.get_by(Play, code: play_attrs.code) do
        %Play{} = existing_play ->
          Repo.rollback({:play_already_exists, existing_play.code})

        nil ->
          case Catalogue.create_play(play_attrs) do
            {:ok, play} ->
              play

            {:error, changeset} ->
              Repo.rollback(changeset)
          end
      end

    if file_desc do
      import_editors(file_desc, play)
      import_sources(file_desc, play)
    end

    play
  end

  defp extract_play_attrs(file_desc, encoding_desc) do
    title_stmt = file_desc && find_child(elem(file_desc, 2), "titleStmt")
    publication_stmt = file_desc && find_child(elem(file_desc, 2), "publicationStmt")
    extent = file_desc && find_child(elem(file_desc, 2), "extent")

    titles = if title_stmt, do: find_children(elem(title_stmt, 2), "title"), else: []
    authors = if title_stmt, do: find_children(elem(title_stmt, 2), "author"), else: []

    main_title = Enum.find(titles, fn {_, attrs, _} -> !has_attr?(attrs, "key") end)
    sort_title = Enum.find(titles, fn {_, attrs, _} -> attr_value(attrs, "key") == "orden" end)
    code_title = Enum.find(titles, fn {_, attrs, _} -> attr_value(attrs, "key") == "archivo" end)

    original_title_el =
      Enum.find(titles, fn {_, attrs, _} -> attr_value(attrs, "type") == "original" end)

    # Extract sponsor and funder from titleStmt
    sponsor_el = if title_stmt, do: find_child(elem(title_stmt, 2), "sponsor"), else: nil
    funder_el = if title_stmt, do: find_child(elem(title_stmt, 2), "funder"), else: nil

    main_author = Enum.find(authors, fn {_, attrs, _} -> !has_attr?(attrs, "key") end)
    sort_author = Enum.find(authors, fn {_, attrs, _} -> attr_value(attrs, "key") == "orden" end)

    # Extract code from either archivo title or idno
    code = if code_title, do: text_content(code_title), else: extract_idno(publication_stmt)

    # Extract verse count from extent
    verse_count = if extent, do: extract_verse_count(extent), else: nil

    # Extract publication info
    {pub_place, pub_date, publisher_text, availability, licence_url, licence_text, authority_text} =
      extract_publication(publication_stmt)

    # Extract EMOTHE-specific idno
    emothe_id = extract_emothe_idno(publication_stmt)

    # Extract project/editorial from encodingDesc
    {project_desc, editorial_decl} = extract_encoding(encoding_desc)

    attribution =
      if main_author do
        attr_value(elem(main_author, 1), "ana")
      end

    %{
      title: safe_text(main_title) |> normalize_imported_title(),
      title_sort: safe_text(sort_title),
      code: clean_code(code || "UNKNOWN"),
      original_title: safe_text(original_title_el),
      author_name: safe_text(main_author),
      author_sort: safe_text(sort_author),
      author_attribution: attribution,
      verse_count: verse_count,
      is_verse: verse_count != nil && verse_count > 0,
      pub_place: pub_place,
      publication_date: pub_date,
      publisher: publisher_text,
      availability_note: availability,
      licence_url: licence_url,
      licence_text: licence_text,
      emothe_id: emothe_id,
      sponsor: safe_text(sponsor_el),
      funder: safe_text(funder_el),
      authority: authority_text,
      project_description: project_desc,
      editorial_declaration: editorial_decl
    }
  end

  defp extract_idno(nil), do: nil

  defp extract_idno({_name, _attrs, children}) do
    idno = find_child(children, "idno")
    if idno, do: text_content(idno), else: nil
  end

  # Extract the EMOTHE-specific idno (type="EMOTHE")
  defp extract_emothe_idno(nil), do: nil

  defp extract_emothe_idno({_name, _attrs, children}) do
    idnos = find_children(children, "idno")

    emothe_idno =
      Enum.find(idnos, fn {_, attrs, _} -> attr_value(attrs, "type") == "EMOTHE" end)

    if emothe_idno, do: text_content(emothe_idno), else: nil
  end

  defp extract_verse_count({_name, _attrs, _children} = extent) do
    text = text_content(extent)

    case Regex.run(~r/(\d+)/, text) do
      [_, num] -> String.to_integer(num)
      _ -> nil
    end
  end

  defp extract_publication(nil), do: {nil, nil, nil, nil, nil, nil, nil}

  defp extract_publication({_name, _attrs, children}) do
    pub_place = find_child(children, "pubPlace")
    date = find_child(children, "date")
    publisher = find_child(children, "publisher")
    availability = find_child(children, "availability")
    authority = find_child(children, "authority")

    # Extract licence details from within availability
    {licence_url, licence_text} =
      case availability do
        {_, _, avail_children} ->
          licence_el = find_child(avail_children, "licence")

          case licence_el do
            {_, attrs, _} ->
              url = attr_value(attrs, "target")
              text = text_content(licence_el)
              {url, text}

            _ ->
              {nil, nil}
          end

        _ ->
          {nil, nil}
      end

    # availability_note: only the <p> text, not the licence text
    availability_text =
      case availability do
        {_, _, avail_children} ->
          avail_children
          |> Enum.filter(fn
            {"p", _, _} -> true
            _ -> false
          end)
          |> Enum.map(&text_content/1)
          |> Enum.join("\n\n")
          |> String.trim()
          |> case do
            "" -> nil
            t -> t
          end

        _ ->
          safe_text(availability)
      end

    {
      safe_text(pub_place),
      safe_text(date),
      safe_text(publisher),
      availability_text,
      licence_url,
      licence_text,
      safe_text(authority)
    }
  end

  defp extract_encoding(nil), do: {nil, nil}

  defp extract_encoding({_name, _attrs, children}) do
    project_desc = find_child(children, "projectDesc")
    editorial_decl = find_child(children, "editorialDecl")

    {
      safe_text(project_desc),
      safe_text(editorial_decl)
    }
  end

  # --- Editors ---

  defp import_editors(file_desc, play) do
    title_stmt = find_child(elem(file_desc, 2), "titleStmt")
    edition_stmt = find_child(elem(file_desc, 2), "editionStmt")

    # Principal investigator and titleStmt editors
    if title_stmt do
      title_stmt_children = elem(title_stmt, 2)

      principal = find_child(title_stmt_children, "principal")

      if principal do
        Catalogue.create_play_editor(%{
          play_id: play.id,
          person_name: text_content(principal),
          role: "principal",
          position: 0
        })
      end

      # Translators specified directly in titleStmt as <editor role="translator">
      title_editors = find_children(title_stmt_children, "editor")

      title_editors
      |> Enum.with_index(1)
      |> Enum.each(fn {{_, attrs, ed_children}, idx} ->
        role = attr_value(attrs, "role")

        normalized_role =
          case role do
            "translator" -> "translator"
            "researcher" -> "researcher"
            _ -> nil
          end

        if normalized_role do
          # Name may be in <persName> or direct text
          person_name =
            case find_child(ed_children, "persName") do
              nil -> text_content({"editor", attrs, ed_children})
              el -> text_content(el)
            end

          Catalogue.create_play_editor(%{
            play_id: play.id,
            person_name: person_name,
            role: normalized_role,
            position: idx
          })
        end
      end)

      # respStmt elements in titleStmt (common in EMOTHE files)
      resp_stmts_in_title = find_children(title_stmt_children, "respStmt")

      resp_stmts_in_title
      |> Enum.with_index(100)
      |> Enum.each(fn {{_name, _attrs, children}, idx} ->
        person = find_child(children, "persName")
        org = find_child(children, "orgName")
        resp = find_child(children, "resp")

        role =
          case safe_text(resp) do
            text when is_binary(text) ->
              cond do
                String.contains?(text, "Edición") -> "editor"
                String.contains?(text, "Revisión") -> "reviewer"
                true -> "digital_editor"
              end

            _ ->
              "digital_editor"
          end

        if person do
          Catalogue.create_play_editor(%{
            play_id: play.id,
            person_name: text_content(person),
            role: role,
            organization: safe_text(org),
            position: idx
          })
        end
      end)
    end

    # Edition editors (from editionStmt)
    if edition_stmt do
      resp_stmts = find_children(elem(edition_stmt, 2), "respStmt")

      resp_stmts
      |> Enum.with_index(200)
      |> Enum.each(fn {{_name, _attrs, children}, idx} ->
        person = find_child(children, "persName")
        org = find_child(children, "orgName")
        resp = find_child(children, "resp")

        role =
          case safe_text(resp) do
            text when is_binary(text) ->
              cond do
                String.contains?(text, "Edición") -> "editor"
                String.contains?(text, "Revisión") -> "reviewer"
                true -> "digital_editor"
              end

            _ ->
              "digital_editor"
          end

        if person do
          Catalogue.create_play_editor(%{
            play_id: play.id,
            person_name: text_content(person),
            role: role,
            organization: safe_text(org),
            position: idx
          })
        end
      end)
    end
  end

  # --- Sources ---

  defp import_sources(file_desc, play) do
    source_desc = find_child(elem(file_desc, 2), "sourceDesc")

    if source_desc do
      bibls = find_children(elem(source_desc, 2), "bibl")

      bibls
      |> Enum.with_index()
      |> Enum.each(fn {{_name, _attrs, children}, idx} ->
        editor_el = find_child(children, "editor")

        editor_role =
          case editor_el do
            {_, attrs, _} -> attr_value(attrs, "role")
            _ -> nil
          end

        Catalogue.create_play_source(%{
          play_id: play.id,
          title: safe_text(find_child(children, "title")),
          author: safe_text(find_child(children, "author")),
          editor: safe_text(editor_el),
          editor_role: editor_role,
          note: safe_text(find_child(children, "note")),
          language: safe_text(find_child(children, "lang")),
          position: idx
        })
      end)
    end
  end

  # --- Text content (front, body, back) ---

  defp import_text({_name, _attrs, children}, play) do
    front = find_child(children, "front")
    body = find_child(children, "body")

    position = 0

    position =
      if front do
        import_front(front, play, position)
      else
        position
      end

    if body do
      import_body(body, play, position)
    end
  end

  # --- Front matter ---

  defp import_front({_name, _attrs, children}, play, start_pos) do
    # Import cast list and front matter divs
    pos = start_pos

    Enum.reduce(children, pos, fn
      {"titlePage", _attrs, _children}, acc ->
        # Skip title page, it's metadata we already have
        acc

      {"div", attrs, div_children} = _div, acc ->
        type = attr_value(attrs, "type") || "front"
        import_front_div(type, div_children, play, acc)

      _, acc ->
        acc
    end)
  end

  defp import_front_div("elenco", children, play, pos) do
    # Cast list
    cast_list = find_child(children, "castList")

    if cast_list do
      import_cast_list(cast_list, play)
    end

    # Create a division for the elenco
    {:ok, _div} =
      PlayContent.create_division(%{
        play_id: play.id,
        type: "elenco",
        title: safe_text(find_child(children, "head")),
        position: pos
      })

    pos + 1
  end

  defp import_front_div(type, children, play, pos) do
    # Generic front matter div (dedication, editorial note, etc.)
    heading = safe_text(find_child(children, "head"))

    # Store as editorial note
    paragraphs =
      children
      |> find_children("p")
      |> Enum.map(&text_content/1)
      |> Enum.join("\n\n")

    if paragraphs != "" do
      section_type =
        case type do
          "introduccion_editor" -> "introduccion_editor"
          "dedicatoria" -> "dedicatoria"
          "argumento" -> "argumento"
          "prologo" -> "prologo"
          _ -> "nota"
        end

      Catalogue.create_play_editorial_note(%{
        play_id: play.id,
        section_type: section_type,
        heading: heading,
        content: paragraphs,
        position: pos
      })
    end

    pos + 1
  end

  # --- Cast list ---

  defp import_cast_list({_name, _attrs, children}, play) do
    cast_items = find_children(children, "castItem")

    cast_items
    |> Enum.with_index()
    |> Enum.each(fn {{_name, attrs, item_children}, idx} ->
      role = find_child(item_children, "role")
      role_desc = find_child(item_children, "roleDesc")
      is_hidden = attr_value(attrs, "ana") == "oculto"

      if role do
        {_role_name, role_attrs, _role_children} = role
        xml_id = attr_value(role_attrs, "xml:id") || attr_value(role_attrs, "id")
        name = text_content(role) |> String.trim()

        # Clean xml_id (some have newlines)
        xml_id = if xml_id, do: String.trim(xml_id), else: name

        PlayContent.create_character_unless_exists(%{
          play_id: play.id,
          xml_id: xml_id,
          name: name,
          description: safe_text(role_desc),
          is_hidden: is_hidden,
          position: idx
        })
      end
    end)
  end

  # --- Body (acts, scenes, speeches, etc.) ---

  defp import_body({_name, _attrs, children}, play, start_pos) do
    children
    |> Enum.filter(fn
      {name, _, _} -> name in ["div1", "div"]
      _ -> false
    end)
    |> Enum.with_index(start_pos)
    |> Enum.each(fn {{_name, attrs, act_children}, pos} ->
      type = (attr_value(attrs, "type") || "acto") |> String.downcase()
      number = parse_int(attr_value(attrs, "n"))
      heading = safe_text(find_child(act_children, "head"))

      {:ok, act_div} =
        PlayContent.create_division(%{
          play_id: play.id,
          type: type,
          number: number,
          title: heading,
          position: pos
        })

      import_act_content(act_children, play, act_div)
    end)
  end

  defp import_act_content(children, play, act_div) do
    # Process children sequentially, tracking element position
    {_pos, _scene_pos} =
      Enum.reduce(children, {0, 0}, fn
        {"head", _, _}, acc ->
          # Already handled as division title
          acc

        {"div2", attrs, scene_children}, {el_pos, scene_pos} ->
          # Scene subdivision
          scene_type = (attr_value(attrs, "type") || "escena") |> String.downcase()
          number = parse_int(attr_value(attrs, "n"))
          heading = safe_text(find_child(scene_children, "head"))

          {:ok, scene_div} =
            PlayContent.create_division(%{
              play_id: play.id,
              parent_id: act_div.id,
              type: scene_type,
              number: number,
              title: heading,
              position: scene_pos
            })

          new_el_pos = import_scene_content(scene_children, play, scene_div, el_pos)
          {new_el_pos, scene_pos + 1}

        {"sp", attrs, sp_children}, {el_pos, scene_pos} ->
          new_pos = import_speech(attrs, sp_children, play, act_div, el_pos)
          {new_pos, scene_pos}

        {"stage", _attrs, _} = stage, {el_pos, scene_pos} ->
          import_stage_direction(stage, play, act_div, nil, el_pos)
          {el_pos + 1, scene_pos}

        _, acc ->
          acc
      end)
  end

  defp import_scene_content(children, play, scene_div, start_pos) do
    Enum.reduce(children, start_pos, fn
      {"head", _, _}, pos ->
        pos

      {"sp", attrs, sp_children}, pos ->
        import_speech(attrs, sp_children, play, scene_div, pos)

      {"stage", _, _} = stage, pos ->
        import_stage_direction(stage, play, scene_div, nil, pos)
        pos + 1

      _, pos ->
        pos
    end)
  end

  # --- Speech ---

  defp import_speech(attrs, children, play, division, start_pos) do
    who = attr_value(attrs, "who")
    speaker_elem = find_child(children, "speaker")
    speaker_label = safe_text(speaker_elem)

    # Resolve character from who attribute
    character_id = resolve_character(play.id, who)

    {:ok, speech} =
      PlayContent.create_element(%{
        play_id: play.id,
        division_id: division.id,
        type: "speech",
        speaker_label: speaker_label,
        character_id: character_id,
        position: start_pos
      })

    # Import child elements (lg groups, individual l elements, stage directions, p elements)
    _child_pos =
      Enum.reduce(children, 0, fn
        {"speaker", _, _}, pos ->
          pos

        {"lg", attrs, lg_children}, pos ->
          import_line_group(attrs, lg_children, play, division, speech, pos)

        {"l", _, _} = line, pos ->
          import_verse_line(line, play, division, speech, nil, pos)
          pos + 1

        {"stage", _, _} = stage, pos ->
          import_stage_direction(stage, play, division, speech.id, pos)
          pos + 1

        {"p", _, _} = para, pos ->
          import_prose(para, play, division, speech, pos)
          pos + 1

        _, pos ->
          pos
      end)

    start_pos + 1
  end

  # --- Line group ---

  defp import_line_group(attrs, children, play, division, speech, start_pos) do
    verse_type = attr_value(attrs, "type")
    part = attr_value(attrs, "part")

    {:ok, lg} =
      PlayContent.create_element(%{
        play_id: play.id,
        division_id: division.id,
        parent_id: speech.id,
        type: "line_group",
        verse_type: verse_type,
        part: part,
        position: start_pos
      })

    Enum.reduce(children, 0, fn
      {"l", _, _} = line, pos ->
        import_verse_line(line, play, division, lg, speech.character_id, pos)
        pos + 1

      {"stage", _, _} = stage, pos ->
        import_stage_direction(stage, play, division, lg.id, pos)
        pos + 1

      _, pos ->
        pos
    end)

    start_pos + 1
  end

  # --- Verse line ---

  defp import_verse_line(
         {name, attrs, children},
         play,
         division,
         parent,
         character_id,
         pos
       ) do
    line_id = attr_value(attrs, "xml:id") || attr_value(attrs, "id")
    line_number = parse_int(attr_value(attrs, "n"))
    part = attr_value(attrs, "part")
    rend = attr_value(attrs, "rend")
    is_aside = aside_delivery?(children)
    content = verse_line_content({name, attrs, children}, is_aside)

    char_id = character_id || parent.character_id

    PlayContent.create_element(%{
      play_id: play.id,
      division_id: division.id,
      parent_id: parent.id,
      character_id: char_id,
      type: "verse_line",
      content: content,
      line_number: line_number,
      line_id: line_id,
      part: part,
      rend: rend,
      is_aside: is_aside,
      position: pos
    })
  end

  # Returns true if the children of an <l> element indicate an aside, either via:
  # - <stage type="delivery">[Aparte.]</stage>
  # - <seg type="aside">...</seg>
  defp aside_delivery?(children) when is_list(children) do
    Enum.any?(children, fn
      {"stage", attrs, stage_children} ->
        attr_value(attrs, "type") == "delivery" and
          String.match?(
            text_content({"stage", attrs, stage_children}),
            ~r/aparte/i
          )

      {"seg", attrs, _} ->
        attr_value(attrs, "type") == "aside"

      _ ->
        false
    end)
  end

  defp aside_delivery?(_), do: false

  # Extracts the spoken content from a verse line element.
  # For aside lines, prefers <seg type="aside"> children; falls back to
  # stripping stage direction text if no <seg> is present.
  defp verse_line_content({_name, _attrs, children}, true) do
    aside_segs =
      Enum.filter(children, fn
        {"seg", attrs, _} -> attr_value(attrs, "type") == "aside"
        _ -> false
      end)

    if aside_segs != [] do
      aside_segs
      |> Enum.map(&text_content/1)
      |> Enum.join(" ")
      |> String.trim()
    else
      # No <seg type="aside">: strip the stage direction and use remaining text
      non_stage =
        Enum.reject(children, fn
          {"stage", _, _} -> true
          _ -> false
        end)

      non_stage
      |> Enum.map(fn
        text when is_binary(text) -> String.trim(text)
        child when is_tuple(child) -> text_content(child)
        _ -> ""
      end)
      |> Enum.join(" ")
      |> String.replace(~r/\s+/, " ")
      |> String.trim()
    end
  end

  defp verse_line_content(line, false), do: text_content(line)

  # --- Stage direction ---

  defp import_stage_direction({_name, _attrs, _children} = stage, play, division, parent_id, pos) do
    content = text_content(stage)

    PlayContent.create_element(%{
      play_id: play.id,
      division_id: division.id,
      parent_id: parent_id,
      type: "stage_direction",
      content: content,
      position: pos
    })
  end

  # --- Prose ---

  defp import_prose({_name, _attrs, children} = para, play, division, speech, pos) do
    is_aside = aside_in_children?(children)
    content = if is_aside, do: prose_aside_content(children), else: text_content(para)

    PlayContent.create_element(%{
      play_id: play.id,
      division_id: division.id,
      parent_id: speech.id,
      character_id: speech.character_id,
      type: "prose",
      content: content,
      is_aside: is_aside,
      position: pos
    })
  end

  # Check if children contain a <seg type="aside"> element
  defp aside_in_children?(children) when is_list(children) do
    Enum.any?(children, fn
      {"seg", attrs, _} -> attr_value(attrs, "type") == "aside"
      _ -> false
    end)
  end

  defp aside_in_children?(_), do: false

  # Extract aside content from prose children, preferring <seg type="aside"> text
  defp prose_aside_content(children) do
    children
    |> Enum.filter(fn
      {"seg", attrs, _} -> attr_value(attrs, "type") == "aside"
      _ -> false
    end)
    |> Enum.map(&text_content/1)
    |> Enum.join(" ")
    |> String.trim()
  end

  # --- Character resolution ---

  defp resolve_character(_play_id, nil), do: nil

  defp resolve_character(play_id, who) do
    # who is like "#ALFONSO" or "#DONPEDRODELARA.\n"
    xml_id =
      who
      |> String.replace("#", "")
      |> String.trim()

    case PlayContent.find_character_by_xml_id(play_id, xml_id) do
      nil -> nil
      char -> char.id
    end
  end

  # --- XML helpers ---

  defp find_child(children, name) when is_list(children) do
    Enum.find(children, fn
      {^name, _, _} -> true
      _ -> false
    end)
  end

  defp find_child(_, _), do: nil

  defp find_children(children, name) when is_list(children) do
    Enum.filter(children, fn
      {^name, _, _} -> true
      _ -> false
    end)
  end

  defp find_children(_, _), do: []

  defp text_content({_name, _attrs, children}) do
    children
    |> Enum.map(fn
      text when is_binary(text) -> String.trim(text)
      child when is_tuple(child) -> text_content(child)
      _ -> ""
    end)
    |> Enum.join(" ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp text_content(text) when is_binary(text), do: String.trim(text)
  defp text_content(_), do: ""

  defp safe_text(nil), do: nil
  defp safe_text(element) when is_tuple(element), do: text_content(element)
  defp safe_text(text) when is_binary(text), do: String.trim(text)

  defp attr_value(attrs, key) when is_list(attrs) do
    case List.keyfind(attrs, key, 0) do
      {^key, value} -> value
      nil -> nil
    end
  end

  defp attr_value(_, _), do: nil

  defp has_attr?(attrs, key), do: attr_value(attrs, key) != nil

  defp parse_int(nil), do: nil

  defp parse_int(str) do
    case Integer.parse(str) do
      {num, _} -> num
      :error -> nil
    end
  end

  defp clean_code(code) do
    code
    |> String.trim()
    |> String.replace(~r/[^a-zA-Z0-9_]/, "")
  end

  defp normalize_imported_title(nil), do: nil

  defp normalize_imported_title(title) when is_binary(title) do
    normalized_title = String.trim(title)

    if all_caps_text?(normalized_title) do
      normalized_title
      |> then(&Regex.split(~r/(\s+)/u, &1, include_captures: true))
      |> Enum.reduce({[], true}, fn segment, {acc, first_word?} ->
        if Regex.match?(~r/^\s+$/u, segment) do
          {[segment | acc], first_word?}
        else
          formatted_segment = format_title_segment(segment, first_word?)
          {[formatted_segment | acc], false}
        end
      end)
      |> elem(0)
      |> Enum.reverse()
      |> Enum.join()
    else
      normalized_title
    end
  end

  defp all_caps_text?(text) do
    String.match?(text, ~r/\p{L}/u) && text == String.upcase(text) &&
      text != String.downcase(text)
  end

  defp format_title_segment(segment, first_word?) do
    case Regex.run(~r/^([^\p{L}\p{N}]*)([\p{L}\p{N}'’\-]+)([^\p{L}\p{N}]*)$/u, segment) do
      [_, leading, core, trailing] ->
        downcased_core = String.downcase(core)

        formatted_core =
          cond do
            Regex.match?(~r/^[ivxlcdm]+$/iu, core) ->
              String.upcase(core)

            not first_word? and MapSet.member?(@title_small_words, downcased_core) ->
              downcased_core

            true ->
              String.capitalize(downcased_core)
          end

        leading <> formatted_core <> trailing

      _ ->
        segment
    end
  end
end
