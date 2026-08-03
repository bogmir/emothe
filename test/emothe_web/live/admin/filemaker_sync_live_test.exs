defmodule EmotheWeb.Admin.FilemakerSyncLiveTest do
  use EmotheWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Emothe.TestFixtures

  alias Emothe.ActivityLog
  alias Emothe.Catalogue

  describe "access" do
    test "given an admin then the upload form is rendered", %{conn: conn} do
      {:ok, lv, _html} = live(log_in_user(conn, admin_fixture()), ~p"/admin/filemaker")

      assert has_element?(lv, "#upload-form")
    end

    test "given a researcher then the page is refused", %{conn: conn} do
      conn = log_in_user(conn, user_fixture(role: :researcher))

      assert {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, ~p"/admin/filemaker")
      assert flash["error"] == t("You do not have access to that page.")
    end
  end

  @export "test/fixtures/filemaker/export_sample.ndjson"

  defp corpus do
    p38 =
      play_fixture(%{
        "code" => "EMOTHE0038",
        "title" => "Antony and Cleopatra",
        "historical_time" => "edad_media"
      })

    p52 =
      play_fixture(%{
        "code" => "EMOTHE0052",
        "title" => "Antonio y Cleopatra",
        "relationship_type" => "traduccion",
        "parent_play_id" => p38.id
      })

    p211 = play_fixture(%{"code" => "EMOTHE0211", "title" => "El caballero de Olmedo"})

    p393 =
      play_fixture(%{
        "code" => "HIE0393",
        "title" => "The Spanish Bawd",
        "historical_time" => "edad_media"
      })

    al = play_fixture(%{"code" => "AL0001", "title" => "Artelope play"})

    %{p38: p38, p52: p52, p211: p211, p393: p393, al: al}
  end

  defp upload_and_preview(lv, path) do
    lv
    |> file_input("#upload-form", :export, [
      %{name: Path.basename(path), content: File.read!(path), type: "application/x-ndjson"}
    ])
    |> render_upload(Path.basename(path))

    lv |> element("#upload-form") |> render_submit()
  end

  describe "preview" do
    setup do
      corpus()
      :ok
    end

    test "given the export then every bucket is reported", %{conn: conn} do
      {:ok, lv, _html} = live(log_in_user(conn, admin_fixture()), ~p"/admin/filemaker")

      upload_and_preview(lv, @export)

      changes = lv |> element("#changes") |> render()
      assert changes =~ "EMOTHE0038"
      assert changes =~ "EMOTHE0211"
      assert changes =~ "HIE0393"
      refute changes =~ "AL0001"

      assert lv |> element("#unchanged") |> render() =~ "EMOTHE0052"

      missing = lv |> element("#missing") |> render()
      assert missing =~ "AL0001"
      assert missing =~ "EMOTHE0211"

      conflicts = lv |> element("#conflicts") |> render()
      assert conflicts =~ "EMOTHE0038"
      assert conflicts =~ "HIE0393"
    end

    # A play absent from the published index can still carry a T01 research
    # record. EMOTHE0341 is that case in the real export. Presenting the buckets
    # as tabs would imply they are exclusive; they are not.
    test "given a play with research metadata but no index entry then it is in both buckets",
         %{conn: conn} do
      {:ok, lv, _html} = live(log_in_user(conn, admin_fixture()), ~p"/admin/filemaker")

      upload_and_preview(lv, @export)

      assert lv |> element("#changes") |> render() =~ "EMOTHE0211"
      assert lv |> element("#missing") |> render() =~ "EMOTHE0211"
    end

    test "given a new value then the current one is shown beside it", %{conn: conn} do
      {:ok, lv, _html} = live(log_in_user(conn, admin_fixture()), ~p"/admin/filemaker")

      upload_and_preview(lv, @export)
      changes = lv |> element("#changes") |> render()

      assert changes =~ t("Historical time")
      assert changes =~ EmotheWeb.PlayLabels.historical_time_label("siglo_xvii")
    end

    test "given discard then the upload form comes back", %{conn: conn} do
      {:ok, lv, _html} = live(log_in_user(conn, admin_fixture()), ~p"/admin/filemaker")

      upload_and_preview(lv, @export)
      assert has_element?(lv, "#changes")

      lv |> element("button", t("Discard")) |> render_click()

      assert has_element?(lv, "#upload-form")
      refute has_element?(lv, "#changes")
    end
  end

  describe "apply" do
    setup do
      Map.put(corpus(), :admin, admin_fixture())
    end

    test "given no conflict ticked then fills are written and curated values are left alone",
         %{conn: conn, admin: admin, p38: p38, p211: p211, p393: p393} do
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/admin/filemaker")

      upload_and_preview(lv, @export)
      lv |> element("#sync-actions button", t("Apply")) |> render_click()

      # Blank columns filled.
      assert Catalogue.get_play!(p211.id).historical_time == "siglo_xvii"
      assert Catalogue.get_play!(p38.id).language == "en"

      assert Catalogue.get_play!(p38.id).historical_time_note ==
               "First century BC. The play dramatizes events taking place between 40 and 30 BC."

      # Curated values a researcher set are untouched.
      assert Catalogue.get_play!(p38.id).historical_time == "edad_media"
      assert Catalogue.get_play!(p393.id).historical_time == "edad_media"
    end

    test "given one conflict ticked then only that one is overwritten",
         %{conn: conn, admin: admin, p38: p38, p393: p393} do
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/admin/filemaker")

      upload_and_preview(lv, @export)

      lv
      |> element(~s(#conflicts input[phx-value-play-id="#{p393.id}"]))
      |> render_click()

      lv |> element("#sync-actions button", t("Apply")) |> render_click()

      assert Catalogue.get_play!(p393.id).historical_time == "siglo_xvi"
      assert Catalogue.get_play!(p38.id).historical_time == "edad_media"
    end

    # apply_plan/2 already logs; only a LiveView has a user_id to give it. This
    # is the whole provenance argument for the page.
    test "given an apply then every write is attributed to the signed-in admin",
         %{conn: conn, admin: admin, p211: p211} do
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/admin/filemaker")

      upload_and_preview(lv, @export)
      lv |> element("#sync-actions button", t("Apply")) |> render_click()

      entries = ActivityLog.list_entries(play_id: p211.id)

      assert Enum.any?(entries, fn entry ->
               entry.user_id == admin.id and entry.metadata["source"] == "filemaker_index"
             end)
    end

    test "given an apply then the results replace the preview", %{conn: conn, admin: admin} do
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/admin/filemaker")

      upload_and_preview(lv, @export)
      lv |> element("#sync-actions button", t("Apply")) |> render_click()

      assert has_element?(lv, "#results")
      refute has_element?(lv, "#changes")
    end
  end

  # A field with no field_label/1 clause of its own must still render. This is
  # what makes S2b--S2f (place_of_action, composition_date, …) land on this page
  # with no edit to it.
  describe "field labels" do
    test "given an unknown field then the catch-all renders it readably" do
      assert EmotheWeb.Admin.FilemakerSyncLive.field_label(:place_of_action) == "place of action"
    end

    test "given an unknown field then its value renders as text" do
      assert EmotheWeb.Admin.FilemakerSyncLive.value_label(:place_of_action, "Roma", %{}) ==
               "Roma"
    end
  end

  defp t(msgid, bindings \\ []) do
    Gettext.gettext(EmotheWeb.Gettext, msgid, bindings)
  end
end
