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
        family: family,
        composition_date_from: 1606,
        composition_date_to: 1607,
        composition_date_note: "=1606 - =1607"
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

  # The dating index/0 would fill, already stored. A test whose subject is not the dating
  # merges this in so the fill is a no-op and its assertions stay about the field it
  # names. The note argument is whichever source wins for that test: the index header
  # when it calls plan/2, T01's when it passes versions/0.
  defp dated(note \\ "=1606 - =1607") do
    %{
      "composition_date_from" => 1606,
      "composition_date_to" => 1607,
      "composition_date_note" => note
    }
  end

  defp t01_note, do: "desde o posterior 1605 y anterior o hasta 1607; 1606"

  defp versions do
    %{
      "EMOTHE0038" => %{
        code: "EMOTHE0038",
        historical_time: "antiguedad_clasica",
        historical_time_note: "First century BC.",
        composition_date_note: t01_note()
      }
    }
  end

  test "corrects the language of an original stored as Spanish" do
    original = play("EMOTHE0038_AntonyAndCleopatra")

    plan = FilemakerSync.plan(index(), [original])

    assert [%{code: "EMOTHE0038", sets: sets}] = plan.changes
    assert sets.language == "en"
    refute Map.has_key?(sets, :parent_play_id)
  end

  test "marks a translation and links it to the original in the database" do
    original =
      play("EMOTHE0038_AntonyAndCleopatra", Map.put(dated(), "language", "en"))

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
    # Deliberately a code no TEI fixture uses. AL0514_ElAusenteEnElLugar is imported by
    # the roundtrip and TEI-validator suites, and this async insert then blocks on the
    # unique index on plays.code until their transactions end — a statement timeout
    # under load, not a logic failure.
    artelope = play("AL9999_NoEstaEnElIndice")

    plan = FilemakerSync.plan(index(), [artelope])

    assert plan.missing == ["AL9999"]
    assert plan.changes == []
  end

  test "a second pass over an already-synced play changes nothing" do
    original =
      play("EMOTHE0038_AntonyAndCleopatra", Map.put(dated(), "language", "en"))

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

  describe "curated fields are fill-only" do
    test "fills a blank historical time" do
      original = play("EMOTHE0038_AntonyAndCleopatra", %{"language" => "en"})

      plan = FilemakerSync.plan(index(), [original], versions())

      assert [%{code: "EMOTHE0038", sets: sets}] = plan.changes
      assert sets.historical_time == "antiguedad_clasica"
      assert sets.historical_time_note == "First century BC."
      assert plan.conflicts == []
    end

    test "leaves an equal value alone" do
      original =
        play(
          "EMOTHE0038_AntonyAndCleopatra",
          Map.merge(dated(t01_note()), %{
            "language" => "en",
            "historical_time" => "antiguedad_clasica",
            "historical_time_note" => "First century BC."
          })
        )

      plan = FilemakerSync.plan(index(), [original], versions())

      assert plan.changes == []
      assert plan.conflicts == []
      assert plan.unchanged == ["EMOTHE0038"]
    end

    test "reports a curated value that disagrees, and does not write it" do
      original =
        play(
          "EMOTHE0038_AntonyAndCleopatra",
          Map.merge(dated(t01_note()), %{
            "language" => "en",
            "historical_time" => "edad_media"
          })
        )

      plan = FilemakerSync.plan(index(), [original], versions())

      assert [%{field: :historical_time, current: "edad_media", indexed: "antiguedad_clasica"}] =
               Enum.filter(plan.conflicts, &(&1.field == :historical_time))

      # the note was blank, so it still gets filled
      assert [%{sets: sets}] = plan.changes
      assert Map.keys(sets) == [:historical_time_note]
    end

    test "never blanks a curated column the export has nothing for" do
      original =
        play(
          "EMOTHE0038_AntonyAndCleopatra",
          Map.merge(dated(), %{
            "language" => "en",
            "historical_time" => "edad_media"
          })
        )

      plan = FilemakerSync.plan(index(), [original], %{})

      assert plan.changes == []
      assert plan.conflicts == []
    end

    test "the S1 fields still overwrite unconditionally" do
      # language is derived, not curated: the index is authoritative and wins.
      original = play("EMOTHE0038_AntonyAndCleopatra", %{"language" => "es"})

      plan = FilemakerSync.plan(index(), [original], %{})

      assert [%{sets: %{language: "en"}}] = plan.changes
      assert plan.conflicts == []
    end

    test "fills a play that has a version record but no index entry" do
      # EMOTHE0341 is real: it has a T01 research record and was never published,
      # so it is absent from T00. A curated fill must not depend on the index.
      orphan = play("EMOTHE0341_LaEstrellaDeSevilla")

      curated = %{
        "EMOTHE0341" => %{
          code: "EMOTHE0341",
          historical_time: "siglo_xvii",
          historical_time_note: nil
        }
      }

      plan = FilemakerSync.plan(index(), [orphan], curated)

      assert [%{code: "EMOTHE0341", sets: %{historical_time: "siglo_xvii"}}] = plan.changes
      assert plan.missing == ["EMOTHE0341"]
    end

    test "force writes the conflicting value" do
      original =
        play("EMOTHE0038_AntonyAndCleopatra", %{
          "language" => "en",
          "historical_time" => "edad_media"
        })

      plan = FilemakerSync.plan(index(), [original], versions())
      results = FilemakerSync.apply_plan(plan, force: true)

      assert Enum.sort(results) == [{:ok, "EMOTHE0038"}]
      assert Emothe.Catalogue.get_play!(original.id).historical_time == "antiguedad_clasica"
    end

    test "without force the conflicting value survives" do
      original =
        play("EMOTHE0038_AntonyAndCleopatra", %{
          "language" => "en",
          "historical_time" => "edad_media"
        })

      index() |> FilemakerSync.plan([original], versions()) |> FilemakerSync.apply_plan()

      assert Emothe.Catalogue.get_play!(original.id).historical_time == "edad_media"
    end
  end

  describe "composition date" do
    test "fills blank columns from the index, with T01's note winning" do
      original = play("EMOTHE0038_AntonyAndCleopatra", %{"language" => "en"})

      plan = FilemakerSync.plan(index(), [original], versions())

      assert [%{code: "EMOTHE0038", sets: sets}] = plan.changes
      assert sets.composition_date_from == 1606
      assert sets.composition_date_to == 1607
      assert sets.composition_date_note == "desde o posterior 1605 y anterior o hasta 1607; 1606"
    end

    test "falls back to the header note when T01 has none" do
      original = play("EMOTHE0038_AntonyAndCleopatra", %{"language" => "en"})

      plan = FilemakerSync.plan(index(), [original], %{})

      assert [%{sets: sets}] = plan.changes
      assert sets.composition_date_note == "=1606 - =1607"
    end

    test "a translation gets no dating" do
      original = play("EMOTHE0038_AntonyAndCleopatra", %{"language" => "en"})
      translation = play("EMOTHE0052_AntonioYCleopatra")

      plan = FilemakerSync.plan(index(), [original, translation], versions())

      change = Enum.find(plan.changes, &(&1.code == "EMOTHE0052"))
      refute Map.has_key?(change.sets, :composition_date_from)
    end

    test "a typed dating that disagrees is a conflict, not a write" do
      original =
        play("EMOTHE0038_AntonyAndCleopatra", %{
          "language" => "en",
          "composition_date_from" => 1600,
          "composition_date_to" => 1601
        })

      plan = FilemakerSync.plan(index(), [original], versions())

      assert Enum.any?(
               plan.conflicts,
               &(&1.field == :composition_date_from and &1.current == 1600)
             )

      assert Enum.all?(plan.changes, &(not Map.has_key?(&1.sets, :composition_date_from)))
    end

    test "force writes the conflicting dating" do
      original =
        play("EMOTHE0038_AntonyAndCleopatra", %{
          "language" => "en",
          "composition_date_from" => 1600,
          "composition_date_to" => 1601
        })

      plan = FilemakerSync.plan(index(), [original], versions())
      assert [{:ok, "EMOTHE0038"}] = FilemakerSync.apply_plan(plan, force: true)

      assert Emothe.Catalogue.get_play!(original.id).composition_date_from == 1606
    end

    test "a skipped dating is reported and never written" do
      # The index entry as Task 5 leaves it when the parse refuses: no years, no note,
      # only the reason and the text it refused.
      refused =
        index()
        |> put_in(
          ["EMOTHE0038"],
          index()["EMOTHE0038"]
          |> Map.drop([:composition_date_from, :composition_date_to, :composition_date_note])
          |> Map.put(:composition_date_skipped, {:span, "¿1694? y ¿1605?"})
        )

      original = play("EMOTHE0038_AntonyAndCleopatra", %{"language" => "en"})

      plan = FilemakerSync.plan(refused, [original], %{})

      assert [%{code: "EMOTHE0038", reason: :span, value: "¿1694? y ¿1605?"}] = plan.skipped
      assert Enum.all?(plan.changes, &(not Map.has_key?(&1.sets, :composition_date_from)))
    end

    test "running twice changes nothing the second time" do
      original = play("EMOTHE0038_AntonyAndCleopatra", %{"language" => "en"})

      plan = FilemakerSync.plan(index(), [original], versions())
      FilemakerSync.apply_plan(plan)

      second =
        FilemakerSync.plan(index(), [Emothe.Catalogue.get_play!(original.id)], versions())

      assert second.changes == []
      assert second.conflicts == []
    end
  end
end
