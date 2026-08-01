defmodule Emothe.Import.FilemakerSyncTest do
  use Emothe.DataCase, async: true

  import Emothe.TestFixtures

  alias Emothe.Import.FilemakerSync

  # Antony and Cleopatra: EN original + ES translation, as the real index has it.
  defp index do
    family = [%{code: "EMOTHE0038", role: :editor}, %{code: "EMOTHE0052", role: :translator}]

    %{
      "EMOTHE0038" => %{
        code: "EMOTHE0038",
        lang: "en",
        title: "ANTONY AND CLEOPATRA",
        credit: "Barbara Mowat and Paul Werstine, ed.",
        role: :editor,
        work: "24",
        xml: "textosXML/EMOTHE0038_AntonyAndCleopatra.xml",
        family: family
      },
      "EMOTHE0052" => %{
        code: "EMOTHE0052",
        lang: "es",
        title: "ANTONIO Y CLEOPATRA",
        credit: "Miguel Teruel Pozas, tra.",
        role: :translator,
        work: "24",
        xml: "textosXML/EMOTHE0052_AntonioYCleopatra.xml",
        family: family
      }
    }
  end

  defp play(code, attrs \\ %{}) do
    play_fixture(Map.merge(%{"code" => code, "language" => "es"}, attrs))
  end

  test "corrects the language of an original stored as Spanish" do
    original = play("EMOTHE0038_AntonyAndCleopatra")

    plan = FilemakerSync.plan(index(), [original])

    assert [%{code: "EMOTHE0038", sets: sets}] = plan.changes
    assert sets.language == "en"
    refute Map.has_key?(sets, :parent_play_id)
  end

  test "marks a translation and links it to the original in the database" do
    original = play("EMOTHE0038_AntonyAndCleopatra", %{"language" => "en"})
    translation = play("EMOTHE0052_AntonioYCleopatra")

    plan = FilemakerSync.plan(index(), [original, translation])

    assert [%{code: "EMOTHE0052", sets: sets}] = plan.changes
    assert sets.relationship_type == "traduccion"
    assert sets.parent_play_id == original.id
    assert plan.unchanged == ["EMOTHE0038"]
  end

  test "leaves parent_play_id alone when the original is not imported" do
    translation = play("EMOTHE0052_AntonioYCleopatra")

    plan = FilemakerSync.plan(index(), [translation])

    assert [%{sets: sets}] = plan.changes
    assert sets.relationship_type == "traduccion"
    refute Map.has_key?(sets, :parent_play_id)
  end

  test "clears a wrong relationship_type on an original" do
    original =
      play("EMOTHE0038_AntonyAndCleopatra", %{
        "language" => "en",
        "relationship_type" => "adaptacion"
      })

    plan = FilemakerSync.plan(index(), [original])

    assert [%{sets: %{relationship_type: nil}}] = plan.changes
  end

  test "reports codes that are not in the index instead of failing" do
    artelope = play("AL0514_ElAusenteEnElLugar")

    plan = FilemakerSync.plan(index(), [artelope])

    assert plan.missing == ["AL0514"]
    assert plan.changes == []
  end

  test "a second pass over an already-synced play changes nothing" do
    original = play("EMOTHE0038_AntonyAndCleopatra", %{"language" => "en"})

    translation =
      play("EMOTHE0052_AntonioYCleopatra", %{
        "language" => "es",
        "relationship_type" => "traduccion",
        "parent_play_id" => original.id
      })

    plan = FilemakerSync.plan(index(), [original, translation])

    assert plan.changes == []
    assert Enum.sort(plan.unchanged) == ["EMOTHE0038", "EMOTHE0052"]
  end

  describe "apply_plan/2" do
    test "writes the changes and logs one activity entry per play" do
      original = play("EMOTHE0038_AntonyAndCleopatra")
      translation = play("EMOTHE0052_AntonioYCleopatra")

      results =
        index()
        |> FilemakerSync.plan([original, translation])
        |> FilemakerSync.apply_plan()

      assert Enum.sort(results) == [{:ok, "EMOTHE0038"}, {:ok, "EMOTHE0052"}]

      assert Emothe.Catalogue.get_play!(original.id).language == "en"

      reloaded = Emothe.Catalogue.get_play!(translation.id)
      assert reloaded.relationship_type == "traduccion"
      assert reloaded.parent_play_id == original.id

      entries = Emothe.ActivityLog.list_entries(play_id: translation.id)
      assert [entry] = entries
      assert entry.action == "update"
      assert entry.metadata["source"] == "filemaker_index"
      assert entry.changes["relationship_type"] == "traduccion"
    end

    test "applying twice is a no-op the second time" do
      original = play("EMOTHE0038_AntonyAndCleopatra")
      index = index()

      index |> FilemakerSync.plan([original]) |> FilemakerSync.apply_plan()

      second = FilemakerSync.plan(index, [Emothe.Catalogue.get_play!(original.id)])
      assert second.changes == []
    end
  end
end
