defmodule EmotheWeb.PlayShowLiveTest do
  use EmotheWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Emothe.TestFixtures

  test "renders navigation panel with metadata and play section links", %{conn: conn} do
    %{play: play, act: act, scene: scene} = TestFixtures.play_with_structure_fixture()

    {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")

    assert has_element?(view, "#play-sections-panel")
    assert has_element?(view, "#metadata-sections-nav a[href='#meta-overview']")
    assert has_element?(view, "#play-sections-nav a[href='#div-#{act.id}']")
    assert has_element?(view, "#play-sections-nav a[href='#div-#{scene.id}']")
  end

  test "tab navigation switches visible behavior", %{conn: conn} do
    %{play: play} = TestFixtures.play_with_structure_fixture()

    {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")

    assert has_element?(view, "#play-tab-text")
    refute has_element?(view, "#play-tab-characters")

    view
    |> element("#play-tab-nav button[phx-value-tab='characters']")
    |> render_click()

    assert has_element?(view, "#play-tab-characters")
    refute has_element?(view, "#play-tab-text")

    view
    |> element("#play-tab-nav button[phx-value-tab='statistics']")
    |> render_click()

    assert has_element?(view, "#play-tab-statistics")
    refute has_element?(view, "#play-tab-characters")
  end

  test "metadata links appear when metadata exists", %{conn: conn} do
    play = TestFixtures.play_with_metadata_fixture()

    {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")

    assert has_element?(view, "#metadata-sections-nav a[href='#meta-sources']")
    assert has_element?(view, "#metadata-sections-nav a[href='#meta-editors']")
    assert has_element?(view, "#metadata-sections-nav a[href='#meta-note-1']")
  end
end
