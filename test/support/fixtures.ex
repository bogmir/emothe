defmodule Emothe.TestFixtures do
  alias Emothe.Catalogue
  alias Emothe.PlayContent

  def unique_code, do: "PLAY-#{System.unique_integer([:positive])}"

  def play_fixture(attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          "title" => "Play #{System.unique_integer([:positive])}",
          "code" => unique_code(),
          "title_sort" => "Play",
          "author_name" => "Author",
          "author_sort" => "Author",
          "language" => "es",
          "is_verse" => true
        },
        attrs
      )

    {:ok, play} = Catalogue.create_play(attrs)
    play
  end

  def play_with_metadata_fixture do
    play = play_fixture()

    {:ok, _} =
      Catalogue.create_play_source(%{
        play_id: play.id,
        title: "Source title",
        note: "Source note",
        position: 1
      })

    {:ok, _} =
      Catalogue.create_play_editor(%{
        play_id: play.id,
        person_name: "Editor One",
        role: "editor",
        position: 1
      })

    {:ok, _} =
      Catalogue.create_play_editorial_note(%{
        play_id: play.id,
        section_type: "nota",
        heading: "Editorial heading",
        content: "Editorial content",
        position: 1
      })

    Catalogue.get_play_with_all!(play.id)
  end

  def play_with_structure_fixture do
    play = play_fixture(%{"title" => "Structured Play", "author_name" => "Tester"})

    {:ok, character} =
      PlayContent.create_character(%{
        play_id: play.id,
        xml_id: "ALFA",
        name: "ALFA",
        position: 1
      })

    {:ok, act} =
      PlayContent.create_division(%{
        play_id: play.id,
        type: "acto",
        number: 1,
        title: "ACT I",
        position: 1
      })

    {:ok, scene} =
      PlayContent.create_division(%{
        play_id: play.id,
        parent_id: act.id,
        type: "escena",
        number: 1,
        title: "SCENE I",
        position: 1
      })

    {:ok, speech} =
      PlayContent.create_element(%{
        play_id: play.id,
        division_id: scene.id,
        type: "speech",
        speaker_label: "ALFA",
        character_id: character.id,
        position: 1
      })

    {:ok, line_group} =
      PlayContent.create_element(%{
        play_id: play.id,
        division_id: scene.id,
        parent_id: speech.id,
        type: "line_group",
        position: 1
      })

    {:ok, verse_line} =
      PlayContent.create_element(%{
        play_id: play.id,
        division_id: scene.id,
        parent_id: line_group.id,
        character_id: character.id,
        type: "verse_line",
        content: "A verse line",
        line_number: 1,
        part: "M",
        position: 1
      })

    {:ok, prose} =
      PlayContent.create_element(%{
        play_id: play.id,
        division_id: scene.id,
        parent_id: speech.id,
        character_id: character.id,
        type: "prose",
        content: "A prose fragment",
        position: 2
      })

    {:ok, stage_direction} =
      PlayContent.create_element(%{
        play_id: play.id,
        division_id: scene.id,
        type: "stage_direction",
        content: "A stage direction",
        position: 3
      })

    %{
      play: play,
      character: character,
      act: act,
      scene: scene,
      speech: speech,
      line_group: line_group,
      verse_line: verse_line,
      prose: prose,
      stage_direction: stage_direction
    }
  end
end
