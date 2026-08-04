defmodule EmotheWeb.Admin.PlaceListLiveTest do
  use EmotheWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Emothe.Places
  alias Emothe.TestFixtures

  defp t(msgid), do: Gettext.gettext(EmotheWeb.Gettext, msgid)

  defp log_in_researcher(conn) do
    log_in_user(conn, TestFixtures.user_fixture(role: :researcher))
  end

  test "a researcher may reach the gazetteer", %{conn: conn} do
    {:ok, _view, html} = live(log_in_researcher(conn), ~p"/admin/places")
    assert html =~ t("Places")
  end

  test "a logged-out visitor may not", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/admin/places")
  end

  test "a place is created with one name and shows its type and play count", %{conn: conn} do
    {:ok, view, _html} = live(log_in_researcher(conn), ~p"/admin/places")

    view |> element("button", t("New place")) |> render_click()

    view
    |> form("#place-form",
      place: %{
        "type" => "city",
        "names" => %{"0" => %{"name" => "Roma", "language" => "es", "is_preferred" => "true"}}
      }
    )
    |> render_submit()

    # The component notifies the parent via send(self(), :place_saved), which the
    # LiveView processes in its own handle_info — a second, separate round trip
    # from render_submit's own reply. render/1 re-reads the view after that
    # message has landed. See the report for why this differs from the brief text.
    html = render(view)

    assert html =~ "Roma"
    assert html =~ t("City")
    assert [place] = Places.list_places()
    assert place.slug == "roma"
    assert place.play_count == 0
  end

  test "searching matches a non-preferred name variant", %{conn: conn} do
    TestFixtures.place_fixture(%{
      "names" => [
        %{"name" => "Constantinopla", "language" => "es", "is_preferred" => "true"},
        %{"name" => "İstanbul", "language" => "tr"}
      ]
    })

    TestFixtures.place_fixture(%{"name" => "Roma"})

    {:ok, view, _html} = live(log_in_researcher(conn), ~p"/admin/places")

    html =
      view |> element("form[phx-change=search]") |> render_change(%{"search" => "istanbul"})

    assert html =~ "Constantinopla"
    refute html =~ "Roma"
  end

  test "a place used by a play cannot be deleted, and says why", %{conn: conn} do
    play = TestFixtures.play_fixture()
    place = TestFixtures.place_fixture(%{"name" => "Roma"})
    TestFixtures.play_place_fixture(play, place)

    {:ok, view, _html} = live(log_in_researcher(conn), ~p"/admin/places")

    html =
      view |> element("button[phx-value-id='#{place.id}'][phx-click=delete]") |> render_click()

    assert html =~ t("This place is still used by a play. Unlink it there first.")
    assert Places.list_places() != []
  end

  test "an unreferenced place is deleted", %{conn: conn} do
    place = TestFixtures.place_fixture(%{"name" => "Roma"})
    {:ok, view, _html} = live(log_in_researcher(conn), ~p"/admin/places")

    view |> element("button[phx-value-id='#{place.id}'][phx-click=delete]") |> render_click()

    assert Places.list_places() == []
  end

  test "a name that already exists warns instead of silently suffixing", %{conn: conn} do
    TestFixtures.place_fixture(%{"name" => "Woods"})

    {:ok, view, _html} = live(log_in_researcher(conn), ~p"/admin/places")
    view |> element("button", t("New place")) |> render_click()

    html =
      view
      |> form("#place-form",
        place: %{
          "type" => "forest",
          "names" => %{"0" => %{"name" => "Woods", "language" => "es", "is_preferred" => "true"}}
        }
      )
      |> render_change()

    assert html =~ t("A place with this name already exists.")
  end

  test "a Wikidata search fills the coordinates and one name per language", %{conn: conn} do
    {:ok, view, _html} = live(log_in_researcher(conn), ~p"/admin/places")
    view |> element("button", t("New place")) |> render_click()

    view
    |> element("form[phx-change=authority_search]")
    |> render_change(%{"term" => "Roma"})

    html = view |> element("button[phx-value-authority-id=Q220]") |> render_click()

    assert html =~ "41.9028"
    assert html =~ "Rome"
  end

  test "an authority failure is reported and does not crash the form", %{conn: conn} do
    {:ok, view, _html} = live(log_in_researcher(conn), ~p"/admin/places")
    view |> element("button", t("New place")) |> render_click()

    html =
      view
      |> element("form[phx-change=authority_search]")
      |> render_change(%{"term" => "boom"})

    assert html =~ t("The authority is unavailable. Enter the details by hand.")
  end

  # Ruling 2: Places.ensure_slug/2 re-derives the slug from "names" whenever the
  # submitted "slug" is blank. The form must always resubmit the current slug, or
  # editing just the name silently changes a stable identifier that is also a URL
  # and a TEI xml:id.
  test "editing a place's name does not change its slug", %{conn: conn} do
    place = TestFixtures.place_fixture(%{"name" => "Roma"})

    {:ok, view, _html} = live(log_in_researcher(conn), ~p"/admin/places")
    view |> element("button[phx-value-id='#{place.id}'][phx-click=edit]") |> render_click()

    view
    |> form("#place-form",
      place: %{
        "names" => %{"0" => %{"name" => "Rome", "language" => "es", "is_preferred" => "true"}}
      }
    )
    |> render_submit()

    reloaded = Places.get_place!(place.id)
    # The literal slug is the fixture's, not "roma" — what matters is that the name edit
    # did not move it.
    assert reloaded.slug == place.slug
    assert Places.display_name(reloaded) == "Rome"
  end
end
