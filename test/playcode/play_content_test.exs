defmodule Playcode.PlayContentTest do
  use Playcode.DataCase, async: true

  alias Playcode.PlayContent
  alias Playcode.TestFixtures

  # The editor's renumbering helpers. They have no caller outside
  # PlayContentEditorLive, which has no test yet; these stay until it does.
  describe "shift_element_positions/3" do
    test "shifts positions of elements at and after the given position" do
      %{play: play, scene: scene} = TestFixtures.play_with_structure_fixture()

      # Create 3 top-level elements at positions 10, 20, 30
      {:ok, e1} =
        PlayContent.create_element(%{
          play_id: play.id,
          division_id: scene.id,
          type: "speech",
          position: 10
        })

      {:ok, e2} =
        PlayContent.create_element(%{
          play_id: play.id,
          division_id: scene.id,
          type: "speech",
          position: 20
        })

      {:ok, e3} =
        PlayContent.create_element(%{
          play_id: play.id,
          division_id: scene.id,
          type: "speech",
          position: 30
        })

      # Shift positions >= 20 (should affect e2 and e3, not e1)
      PlayContent.shift_element_positions(scene.id, nil, 20)

      assert PlayContent.get_element!(e1.id).position == 10
      assert PlayContent.get_element!(e2.id).position == 21
      assert PlayContent.get_element!(e3.id).position == 31
    end

    test "only shifts elements within the same parent" do
      %{play: play, scene: scene, speech: speech} = TestFixtures.play_with_structure_fixture()

      # Create child elements under speech
      {:ok, c1} =
        PlayContent.create_element(%{
          play_id: play.id,
          division_id: scene.id,
          parent_id: speech.id,
          type: "line_group",
          position: 5
        })

      {:ok, c2} =
        PlayContent.create_element(%{
          play_id: play.id,
          division_id: scene.id,
          parent_id: speech.id,
          type: "line_group",
          position: 10
        })

      # Shift children of speech at position >= 5
      PlayContent.shift_element_positions(scene.id, speech.id, 5)

      assert PlayContent.get_element!(c1.id).position == 6
      assert PlayContent.get_element!(c2.id).position == 11
    end
  end

  describe "shift_line_numbers/2" do
    test "shifts all verse line numbers >= given number in the play" do
      %{play: play, scene: scene, line_group: line_group} =
        TestFixtures.play_with_structure_fixture()

      # The fixture already has a verse_line at line_number 1. Add more.
      {:ok, v2} =
        PlayContent.create_element(%{
          play_id: play.id,
          division_id: scene.id,
          parent_id: line_group.id,
          type: "verse_line",
          content: "v2",
          line_number: 2,
          position: 2
        })

      {:ok, v3} =
        PlayContent.create_element(%{
          play_id: play.id,
          division_id: scene.id,
          parent_id: line_group.id,
          type: "verse_line",
          content: "v3",
          line_number: 3,
          position: 3
        })

      # Shift all >= 2
      PlayContent.shift_line_numbers(play.id, 2)

      assert PlayContent.get_element!(v2.id).line_number == 3
      assert PlayContent.get_element!(v3.id).line_number == 4
    end

    test "preserves split verse groupings (same line_number shifted together)" do
      %{play: play, scene: scene, line_group: line_group} =
        TestFixtures.play_with_structure_fixture()

      # Create a split verse pair at line 5
      {:ok, v5i} =
        PlayContent.create_element(%{
          play_id: play.id,
          division_id: scene.id,
          parent_id: line_group.id,
          type: "verse_line",
          content: "start",
          line_number: 5,
          part: "I",
          position: 10
        })

      {:ok, v5f} =
        PlayContent.create_element(%{
          play_id: play.id,
          division_id: scene.id,
          parent_id: line_group.id,
          type: "verse_line",
          content: "end",
          line_number: 5,
          part: "F",
          position: 11
        })

      # Shift all >= 5
      PlayContent.shift_line_numbers(play.id, 5)

      assert PlayContent.get_element!(v5i.id).line_number == 6
      assert PlayContent.get_element!(v5f.id).line_number == 6
    end
  end

  describe "auto_line_number/3" do
    test "returns previous sibling line_number + 1" do
      %{play: play, scene: scene, line_group: line_group} =
        TestFixtures.play_with_structure_fixture()

      # Fixture has verse_line at position 1, line_number 1
      {:ok, _v2} =
        PlayContent.create_element(%{
          play_id: play.id,
          division_id: scene.id,
          parent_id: line_group.id,
          type: "verse_line",
          content: "v2",
          line_number: 2,
          position: 2
        })

      # New verse at position 3 (end) should get line_number 3
      assert PlayContent.auto_line_number(play.id, line_group.id, 3) == 3
    end

    test "returns next sibling line_number when inserting at start of group" do
      %{play: play, scene: scene, speech: speech} = TestFixtures.play_with_structure_fixture()

      # Create a new empty line_group
      {:ok, lg} =
        PlayContent.create_element(%{
          play_id: play.id,
          division_id: scene.id,
          parent_id: speech.id,
          type: "line_group",
          position: 50
        })

      {:ok, _v1} =
        PlayContent.create_element(%{
          play_id: play.id,
          division_id: scene.id,
          parent_id: lg.id,
          type: "verse_line",
          content: "existing",
          line_number: 10,
          position: 1
        })

      # Inserting at position 0 (before the existing verse) should get line_number 10
      assert PlayContent.auto_line_number(play.id, lg.id, 0) == 10
    end

    test "returns global max + 1 for empty line_group" do
      %{play: play, scene: scene, speech: speech} = TestFixtures.play_with_structure_fixture()

      # Fixture has verse_line with line_number 1. Create empty line_group.
      {:ok, lg} =
        PlayContent.create_element(%{
          play_id: play.id,
          division_id: scene.id,
          parent_id: speech.id,
          type: "line_group",
          position: 50
        })

      # Empty group, global max is 1, so should return 2
      assert PlayContent.auto_line_number(play.id, lg.id, 0) == 2
    end
  end
end
