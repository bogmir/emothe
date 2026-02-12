defmodule Emothe.StatisticsTest do
  use Emothe.DataCase, async: true

  alias Emothe.PlayContent
  alias Emothe.Statistics
  alias Emothe.TestFixtures

  test "get_statistics/1 computes and stores aggregate public metrics" do
    %{play: play, line_group: line_group, character: character, scene: scene} =
      TestFixtures.play_with_structure_fixture()

    {:ok, _aside_verse} =
      PlayContent.create_element(%{
        play_id: play.id,
        division_id: scene.id,
        parent_id: line_group.id,
        character_id: character.id,
        type: "verse_line",
        content: "Aside line",
        line_number: 2,
        is_aside: true,
        part: "F",
        position: 4
      })

    stat = Statistics.get_statistics(play.id)

    assert stat.play_id == play.id
    assert stat.data["num_acts"] == 1
    assert get_in(stat.data, ["scenes", "total"]) == 1
    assert stat.data["total_verses"] == 2
    assert stat.data["split_verses"] == 2
    assert stat.data["total_prose_fragments"] == 1
    assert stat.data["total_stage_directions"] == 1
    assert stat.data["total_asides"] == 1
    assert stat.data["aside_verses"] == 1

    assert [%{"name" => "ALFA", "speeches" => 1}] = stat.data["character_appearances"]
  end

  test "recompute/1 refreshes cached statistics after content changes" do
    %{play: play, line_group: line_group, character: character, scene: scene} =
      TestFixtures.play_with_structure_fixture()

    first = Statistics.get_statistics(play.id)

    {:ok, _new_verse} =
      PlayContent.create_element(%{
        play_id: play.id,
        division_id: scene.id,
        parent_id: line_group.id,
        character_id: character.id,
        type: "verse_line",
        content: "New line",
        line_number: 10,
        position: 10
      })

    refreshed = Statistics.recompute(play.id)

    assert refreshed.id == first.id
    assert refreshed.data["total_verses"] == first.data["total_verses"] + 1
  end
end
