defmodule Emothe.Import.WordParser do
  @moduledoc """
  Parses EMOTHE "premarcado" Word (.docx) files into play content structure.

  The premarcación system uses tags like {v}, {p}, {ac}, {pr} etc. at the start
  of each paragraph to annotate structural elements of a play text.
  """

  @doc """
  Extracts paragraphs from a .docx file as a list of strings.
  """
  def extract_paragraphs(path) do
    with {:ok, zip_handle} <- open_zip(path),
         {:ok, document_xml} <- read_zip_entry(zip_handle, ~c"word/document.xml") do
      paragraphs = extract_paragraphs_from_xml(document_xml)
      {:ok, paragraphs}
    end
  end

  defp open_zip(path) do
    path_charlist = String.to_charlist(path)

    case :zip.unzip(path_charlist, [:memory]) do
      {:ok, entries} -> {:ok, entries}
      {:error, reason} -> {:error, {:zip_error, reason}}
    end
  end

  defp read_zip_entry(entries, entry_name) when is_list(entries) do
    case Enum.find(entries, fn {name, _data} -> name == entry_name end) do
      {_name, data} -> {:ok, data}
      nil -> {:error, {:missing_entry, entry_name}}
    end
  end

  defp extract_paragraphs_from_xml(xml_binary) do
    xml_string = to_string(xml_binary)

    # Parse <w:p> paragraphs, each containing <w:r><w:t> text runs
    # Using regex-based extraction since the XML namespace handling
    # with Saxy.SimpleForm would require namespace awareness
    Regex.scan(~r/<w:p\b[^>]*>.*?<\/w:p>/s, xml_string)
    |> Enum.map(fn [paragraph_xml] ->
      # Extract all <w:t> text content within this paragraph
      Regex.scan(~r/<w:t[^>]*>(.*?)<\/w:t>/s, paragraph_xml)
      |> Enum.map(fn [_full, text] -> text end)
      |> Enum.join("")
    end)
  end

  @doc """
  Parses a single line of premarcado text into a list of tagged segments.

  Returns a list of `{tag, text}` tuples where tag is one of:
  :scene, :stage_direction, :aside, :speaker, :verse, :verse_initial,
  :verse_middle, :verse_final, :prose, :stanza, or :text (untagged).
  """
  def parse_line(line) do
    line
    |> split_into_tag_segments()
    |> Enum.map(fn {tag, text} -> {tag_to_atom(tag), String.trim(text)} end)
  end

  # Tag name regex - case-insensitive
  @tag_pattern ~r/\{(e|ac|ap|p|v|ti|tm|tf|pr|m|a)\}/i

  defp split_into_tag_segments(line) do
    # Split line by tags, keeping the tag names
    parts = Regex.split(@tag_pattern, line, include_captures: true)

    parts
    |> chunk_tag_text([])
    |> Enum.reject(fn {_tag, text} -> tag_empty_filler?(text) end)
  end

  # Recursively pair tags with their following text
  defp chunk_tag_text([], acc), do: Enum.reverse(acc)

  defp chunk_tag_text([head | rest], acc) do
    if Regex.match?(@tag_pattern, head) do
      # Extract the tag name
      [_, tag_name] = Regex.run(@tag_pattern, head)
      # Next element (if any) is the text content
      {text, remaining} =
        case rest do
          [next | more] ->
            if Regex.match?(@tag_pattern, next) do
              {"", rest}
            else
              {next, more}
            end

          [] ->
            {"", []}
        end

      chunk_tag_text(remaining, [{String.downcase(tag_name), text} | acc])
    else
      # Text before any tag — untagged content
      if String.trim(head) != "" do
        chunk_tag_text(rest, [{"text", head} | acc])
      else
        chunk_tag_text(rest, acc)
      end
    end
  end

  defp tag_empty_filler?(_text), do: false

  defp tag_to_atom("e"), do: :scene
  defp tag_to_atom("ac"), do: :stage_direction
  defp tag_to_atom("ap"), do: :aside
  defp tag_to_atom("p"), do: :speaker
  defp tag_to_atom("v"), do: :verse
  defp tag_to_atom("ti"), do: :verse_initial
  defp tag_to_atom("tm"), do: :verse_middle
  defp tag_to_atom("tf"), do: :verse_final
  defp tag_to_atom("pr"), do: :prose
  defp tag_to_atom("m"), do: :stanza
  defp tag_to_atom("a"), do: :act
  defp tag_to_atom("text"), do: :text

  @doc """
  Parses a list of paragraph strings into a structured representation
  of acts, scenes, and elements (without DB interaction).

  Returns `{:ok, %{acts: [...], warnings: [...]}}` or `{:error, reason}`.
  """
  def parse_content(paragraphs) do
    parsed_lines = Enum.map(paragraphs, &parse_line/1)

    {acts, _state} =
      parsed_lines
      |> Enum.reduce({[], %{current_act: nil, current_scene: nil, current_speech: nil}}, fn
        segments, {acts, state} ->
          process_line(segments, acts, state)
      end)

    # Finalize: close any open speech/scene/act
    acts = finalize_structure(acts)

    # If no acts were created, wrap everything in a default act
    acts =
      if acts == [] do
        [%{type: "acto", head: nil, scenes: []}]
      else
        acts
      end

    {:ok, %{acts: acts, warnings: []}}
  end

  # Detect act type from heading text (used by both {A} tag and auto-detection)
  defp detect_act_type(text) do
    trimmed = String.trim(text)

    cond do
      Regex.match?(~r/^JORNADA\b/iu, trimmed) -> "jornada"
      Regex.match?(~r/^PR[OÓ]LOGO\b/iu, trimmed) -> "prologo"
      Regex.match?(~r/^PROLOGUE\b/iu, trimmed) -> "prologo"
      Regex.match?(~r/^EP[IÍ]LOGO\b/iu, trimmed) -> "epilogue"
      Regex.match?(~r/^EPILOGUE\b/iu, trimmed) -> "epilogue"
      true -> "acto"
    end
  end

  # Detect act-level headings from plain untagged text (fallback when no {A} tag)
  defp detect_act_heading(segments) do
    case segments do
      [{:text, text}] ->
        trimmed = String.trim(text)

        cond do
          Regex.match?(~r/^JORNADA\s/i, trimmed) -> {:ok, "jornada", trimmed}
          Regex.match?(~r/^ACTO\s/i, trimmed) -> {:ok, "acto", trimmed}
          Regex.match?(~r/^ACT\s/i, trimmed) -> {:ok, "acto", trimmed}
          Regex.match?(~r/^ACTE\s/i, trimmed) -> {:ok, "acto", trimmed}
          Regex.match?(~r/^ATTO\s/i, trimmed) -> {:ok, "acto", trimmed}
          Regex.match?(~r/^PR[OÓ]LOGO\b/iu, trimmed) -> {:ok, "prologo", trimmed}
          Regex.match?(~r/^PROLOGUE\b/iu, trimmed) -> {:ok, "prologo", trimmed}
          Regex.match?(~r/^EP[IÍ]LOGO\b/iu, trimmed) -> {:ok, "epilogue", trimmed}
          Regex.match?(~r/^EPILOGUE\b/iu, trimmed) -> {:ok, "epilogue", trimmed}
          true -> :not_act
        end

      _ ->
        :not_act
    end
  end

  defp is_untagged_text?(segments) do
    case segments do
      [{:text, _}] -> true
      [] -> true
      _ -> false
    end
  end

  defp process_line(segments, acts, state) do
    cond do
      # Explicit {A} act tag
      has_tag?(segments, :act) ->
        heading = get_tag_text(segments, :act)
        act_type = detect_act_type(heading)
        act = %{type: act_type, head: heading, scenes: [], _open: true}

        {acts ++ [act],
         %{state | current_act: length(acts), current_scene: nil, current_speech: nil}}

      # Auto-detected act heading from plain text (fallback)
      match?({:ok, _, _}, detect_act_heading(segments)) ->
        {:ok, act_type, heading} = detect_act_heading(segments)
        act = %{type: act_type, head: heading, scenes: [], _open: true}

        {acts ++ [act],
         %{state | current_act: length(acts), current_scene: nil, current_speech: nil}}

      has_tag?(segments, :scene) ->
        scene_text = get_tag_text(segments, :scene)
        scene = %{head: scene_text, elements: [], _open: true}
        acts = ensure_act(acts, state)
        acts = append_scene(acts, scene)
        act_idx = length(acts) - 1
        scene_idx = length(List.last(acts).scenes) - 1
        {acts, %{state | current_act: act_idx, current_scene: scene_idx, current_speech: nil}}

      is_untagged_text?(segments) ->
        # Skip untagged text lines (titles, blank lines, etc.)
        {acts, state}

      true ->
        acts = ensure_act(acts, state)
        acts = ensure_scene(acts)
        process_content_segments(segments, acts, state)
    end
  end

  defp has_tag?(segments, tag), do: Enum.any?(segments, fn {t, _} -> t == tag end)

  defp get_tag_text(segments, tag) do
    case Enum.find(segments, fn {t, _} -> t == tag end) do
      {_, text} -> text
      nil -> ""
    end
  end

  defp ensure_act([], _state) do
    [%{type: "acto", head: nil, scenes: [], _open: true}]
  end

  defp ensure_act(acts, _state), do: acts

  defp ensure_scene(acts) do
    act = List.last(acts)

    if act.scenes == [] do
      scene = %{head: nil, elements: [], _open: true}
      List.replace_at(acts, -1, %{act | scenes: [scene]})
    else
      acts
    end
  end

  defp append_scene(acts, scene) do
    act = List.last(acts)
    List.replace_at(acts, -1, %{act | scenes: act.scenes ++ [scene]})
  end

  defp process_content_segments(segments, acts, state) do
    has_speaker = has_tag?(segments, :speaker)

    if has_speaker do
      speaker_label = get_tag_text(segments, :speaker)
      # Collect content elements from this line
      children = build_children(segments)
      speech = %{type: "speech", speaker_label: speaker_label, children: children, _open: true}
      acts = append_element(acts, speech)
      {acts, %{state | current_speech: :open}}
    else
      # No speaker — add content to current speech or as standalone elements
      content_segments =
        Enum.reject(segments, fn {t, _} ->
          t in [:text] and String.trim(elem({t, ""}, 1)) == ""
        end)

      case content_segments do
        [{:stage_direction, text}] ->
          el = %{type: "stage_direction", content: text}
          acts = append_element(acts, el)
          {acts, state}

        [{:stanza, _}] ->
          el = %{type: "line_group", content: ""}
          acts = append_element(acts, el)
          {acts, state}

        _ ->
          # Add as children to current speech if one is open
          children = build_children(segments)

          if state.current_speech == :open and children != [] do
            acts = append_children_to_last_speech(acts, children)
            {acts, state}
          else
            # Standalone elements
            Enum.reduce(children, {acts, state}, fn child, {a, s} ->
              {append_element(a, child), s}
            end)
          end
      end
    end
  end

  defp build_children(segments) do
    segments
    |> Enum.reject(fn {tag, _} -> tag in [:speaker, :scene, :aside, :stanza, :text, :act] end)
    |> Enum.map(fn
      {:verse, text} -> %{type: "verse_line", content: text, part: nil}
      {:verse_initial, text} -> %{type: "verse_line", content: text, part: "I"}
      {:verse_middle, text} -> %{type: "verse_line", content: text, part: "M"}
      {:verse_final, text} -> %{type: "verse_line", content: text, part: "F"}
      {:prose, text} -> %{type: "prose", content: text}
      {:stage_direction, text} -> %{type: "stage_direction", content: text}
      {_other, text} -> %{type: "text", content: text}
    end)
  end

  defp append_element(acts, element) do
    update_last_scene(acts, fn scene ->
      %{scene | elements: scene.elements ++ [element]}
    end)
  end

  defp append_children_to_last_speech(acts, children) do
    update_last_scene(acts, fn scene ->
      elements = scene.elements

      case List.last(elements) do
        %{type: "speech"} = speech ->
          updated = %{speech | children: speech.children ++ children}
          %{scene | elements: List.replace_at(elements, -1, updated)}

        _ ->
          scene
      end
    end)
  end

  defp update_last_scene(acts, fun) do
    act = List.last(acts)
    scene = List.last(act.scenes)
    updated_scene = fun.(scene)
    updated_act = %{act | scenes: List.replace_at(act.scenes, -1, updated_scene)}
    List.replace_at(acts, -1, updated_act)
  end

  defp finalize_structure(acts) do
    acts
    |> Enum.map(fn act ->
      scenes =
        act.scenes
        |> Enum.map(&Map.drop(&1, [:_open]))
        |> Enum.reject(&(&1.elements == []))

      act |> Map.drop([:_open]) |> Map.put(:scenes, scenes)
    end)
    |> Enum.reject(&(&1.scenes == []))
  end

  @doc """
  Imports premarcado content from a .docx file into an existing play.
  Deletes any existing content (divisions, elements, characters) first.

  Returns `{:ok, play}` or `{:error, reason}`.
  """
  def import_content(play_id, path) do
    alias Emothe.{Repo, Catalogue, PlayContent}
    alias Emothe.PlayContent.{Character, Division, Element}
    import Ecto.Query

    with {:ok, paragraphs} <- extract_paragraphs(path),
         {:ok, %{acts: acts}} <- parse_content(paragraphs) do
      Repo.transaction(fn ->
        play = Catalogue.get_play!(play_id)

        # Delete existing content (elements first due to FK, then divisions, then characters)
        Repo.delete_all(from e in Element, where: e.play_id == ^play_id)
        Repo.delete_all(from d in Division, where: d.play_id == ^play_id)
        Repo.delete_all(from c in Character, where: c.play_id == ^play_id)

        # Auto-create characters from unique speaker labels
        character_map = create_characters_from_acts(acts, play_id)

        # Create structure in DB
        verse_counter_ref = :counters.new(1, [:atomics])

        Enum.with_index(acts)
        |> Enum.each(fn {act, act_pos} ->
          {:ok, act_div} =
            PlayContent.create_division(%{
              play_id: play_id,
              type: act.type,
              title: act.head,
              number: act_pos + 1,
              position: act_pos
            })

          Enum.with_index(act.scenes)
          |> Enum.each(fn {scene, scene_pos} ->
            {:ok, scene_div} =
              PlayContent.create_division(%{
                play_id: play_id,
                parent_id: act_div.id,
                type: "escena",
                title: scene.head,
                number: scene_pos + 1,
                position: scene_pos
              })

            create_elements(
              scene.elements,
              play_id,
              scene_div.id,
              nil,
              verse_counter_ref,
              character_map
            )
          end)
        end)

        # Update verse count
        Catalogue.update_verse_count(play_id)

        play
      end)
    end
  end

  defp create_characters_from_acts(acts, play_id) do
    alias Emothe.PlayContent

    speaker_labels =
      acts
      |> Enum.flat_map(& &1.scenes)
      |> Enum.flat_map(& &1.elements)
      |> Enum.filter(&(&1.type == "speech" && &1[:speaker_label] && &1.speaker_label != ""))
      |> Enum.map(& &1.speaker_label)
      |> Enum.uniq()

    speaker_labels
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {label, idx}, acc ->
      xml_id =
        label
        |> String.downcase()
        |> String.replace(~r/[^a-z0-9]+/, "_")
        |> String.trim("_")

      {:ok, char} =
        PlayContent.create_character_unless_exists(%{
          play_id: play_id,
          xml_id: xml_id,
          name: label,
          position: idx
        })

      Map.put(acc, label, char.id)
    end)
  end

  defp create_elements(elements, play_id, division_id, parent_id, verse_counter, character_map) do
    alias Emothe.PlayContent

    elements
    |> Enum.with_index()
    |> Enum.each(fn {element, pos} ->
      case element do
        %{type: "speech"} ->
          character_id = Map.get(character_map, element.speaker_label)

          {:ok, speech} =
            PlayContent.create_element(%{
              play_id: play_id,
              division_id: division_id,
              parent_id: parent_id,
              type: "speech",
              speaker_label: element.speaker_label,
              character_id: character_id,
              position: pos
            })

          children = Map.get(element, :children, [])
          create_children(children, play_id, division_id, speech.id, verse_counter, character_id)

        %{type: "stage_direction"} ->
          PlayContent.create_element(%{
            play_id: play_id,
            division_id: division_id,
            parent_id: parent_id,
            type: "stage_direction",
            content: element.content,
            position: pos
          })

        %{type: "line_group"} ->
          PlayContent.create_element(%{
            play_id: play_id,
            division_id: division_id,
            parent_id: parent_id,
            type: "line_group",
            position: pos
          })

        _ ->
          :ok
      end
    end)
  end

  # Child elements (verse, prose) inherit character_id from their parent speech
  defp create_children(children, play_id, division_id, parent_id, verse_counter, character_id) do
    alias Emothe.PlayContent

    children
    |> Enum.with_index()
    |> Enum.each(fn {element, pos} ->
      case element do
        %{type: "verse_line"} ->
          :counters.add(verse_counter, 1, 1)
          line_num = :counters.get(verse_counter, 1)

          PlayContent.create_element(%{
            play_id: play_id,
            division_id: division_id,
            parent_id: parent_id,
            type: "verse_line",
            content: element.content,
            part: element[:part],
            line_number: line_num,
            character_id: character_id,
            position: pos
          })

        %{type: "prose"} ->
          PlayContent.create_element(%{
            play_id: play_id,
            division_id: division_id,
            parent_id: parent_id,
            type: "prose",
            content: element.content,
            character_id: character_id,
            position: pos
          })

        %{type: "stage_direction"} ->
          PlayContent.create_element(%{
            play_id: play_id,
            division_id: division_id,
            parent_id: parent_id,
            type: "stage_direction",
            content: element.content,
            position: pos
          })

        _ ->
          :ok
      end
    end)
  end
end
