defmodule EmotheWeb.Admin.PlayPlacesLiveTest do
  use EmotheWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Emothe.Places
  alias Emothe.TestFixtures

  defp t(msgid), do: Gettext.gettext(EmotheWeb.Gettext, msgid)

  defp setup_play(conn) do
    conn = log_in_user(conn, TestFixtures.user_fixture(role: :researcher))
    play = TestFixtures.play_fixture()
    {conn, play}
  end

  test "the context bar offers Places beside Sources and Content", %{conn: conn} do
    {conn, play} = setup_play(conn)
    {:ok, _view, html} = live(conn, ~p"/admin/plays/#{play.id}/places")

    assert html =~ ~p"/admin/plays/#{play.id}/sources"
    assert html =~ ~p"/admin/plays/#{play.id}/content"
    assert html =~ t("Places")
  end

  test "an existing place is linked from the picker", %{conn: conn} do
    {conn, play} = setup_play(conn)
    place = TestFixtures.place_fixture(%{"name" => "Roma"})

    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/places")

    html =
      view
      |> element("form[phx-submit=link]")
      |> render_submit(%{"place_id" => place.id, "role" => "setting"})

    assert html =~ "Roma"
    assert [link] = Places.list_play_places(play.id)
    assert link.role == "setting"
    assert link.origin == "manual"
  end

  test "role and note are editable in place", %{conn: conn} do
    {conn, play} = setup_play(conn)
    place = TestFixtures.place_fixture(%{"name" => "Miseno"})
    link = TestFixtures.play_place_fixture(play, place)

    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/places")

    view
    |> element("form[phx-submit=update_link][id='link-form-#{link.id}']")
    |> render_submit(%{"play_place" => %{"role" => "mentioned", "note" => "Named, not staged."}})

    assert [updated] = Places.list_play_places(play.id)
    assert updated.role == "mentioned"
    assert updated.note == "Named, not staged."
  end

  test "links reorder", %{conn: conn} do
    {conn, play} = setup_play(conn)
    roma = TestFixtures.place_fixture(%{"name" => "Roma"})
    miseno = TestFixtures.place_fixture(%{"name" => "Miseno"})
    first = TestFixtures.play_place_fixture(play, roma)
    _second = TestFixtures.play_place_fixture(play, miseno)

    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/places")

    view |> element("button[phx-click=move_down][phx-value-id='#{first.id}']") |> render_click()

    assert Places.list_play_places(play.id)
           |> Enum.map(&Places.display_name(&1.place, "es")) == ["Miseno", "Roma"]
  end

  test "unlinking keeps the place in the gazetteer", %{conn: conn} do
    {conn, play} = setup_play(conn)
    place = TestFixtures.place_fixture(%{"name" => "Roma"})
    link = TestFixtures.play_place_fixture(play, place)

    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/places")

    view |> element("button[phx-click=unlink][phx-value-id='#{link.id}']") |> render_click()

    assert Places.list_play_places(play.id) == []
    assert Places.list_places() != []
  end

  test "a new place is created and linked in one pass", %{conn: conn} do
    {conn, play} = setup_play(conn)
    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/places")

    view |> element("button", t("New place")) |> render_click()

    view
    |> form("#place-form",
      place: %{
        "type" => "city",
        "names" => %{
          "0" => %{"name" => "Alexandría", "language" => "es", "is_preferred" => "true"}
        }
      }
    )
    |> render_submit()

    # PlaceFormComponent notifies the parent via send(self(), {:place_saved, place}),
    # which this LiveView processes in its own handle_info — a second, separate round
    # trip from render_submit's own reply. render/1 re-reads the view after that
    # message has landed. Same mechanism as PlaceListLiveTest's "a place is created…".
    render(view)

    assert [link] = Places.list_play_places(play.id)
    assert Places.display_name(link.place, "es") == "Alexandría"
  end
end
