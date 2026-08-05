defmodule EmotheWeb.Admin.PlayFormLiveTest do
  use EmotheWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Emothe.Catalogue
  alias Emothe.TestFixtures

  defp log_in_admin(conn) do
    log_in_user(conn, Emothe.TestFixtures.admin_fixture())
  end

  describe "Play form behaviors" do
    test "given valid data when creating a play then user is redirected to detail", %{conn: conn} do
      conn = log_in_admin(conn)
      code = TestFixtures.unique_code()

      {:ok, view, _html} = live(conn, ~p"/admin/plays/new")

      params = %{
        "play" => %{
          "title" => "BDD Play",
          "code" => code,
          "author_name" => "Behavior Author",
          "language" => "es",
          "is_verse" => "true"
        }
      }

      view
      |> element("form[phx-submit]")
      |> render_submit(params)

      created = Catalogue.get_play_by_code!(code)
      assert_redirect(view, ~p"/admin/plays/#{created.id}")
    end

    test "given invalid data when creating a play then errors are shown and no redirect", %{
      conn: conn
    } do
      conn = log_in_admin(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/plays/new")

      view
      |> element("form[phx-submit]")
      |> render_submit(%{"play" => %{"title" => "", "code" => ""}})

      html = render(view)
      assert html =~ "no puede estar en blanco"
      assert html =~ "Nueva obra"
    end

    test "given existing play when editing then updated data is persisted", %{conn: conn} do
      conn = log_in_admin(conn)
      play = TestFixtures.play_fixture(%{"title" => "Original Title"})

      {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/edit")

      view
      |> element("form[phx-submit]")
      |> render_submit(%{"play" => %{"title" => "Updated Title", "code" => play.code}})

      assert_redirect(view, ~p"/admin/plays/#{play.id}")
      assert Catalogue.get_play!(play.id).title == "Updated Title"
    end

    test "given a historical time when saving then it is persisted", %{conn: conn} do
      conn = log_in_admin(conn)
      play = TestFixtures.play_fixture()

      {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/edit")

      assert has_element?(view, "select[name='play[historical_time]']")
      assert has_element?(view, "textarea[name='play[historical_time_note]']")

      view
      |> element("form[phx-submit]")
      |> render_submit(%{
        "play" => %{
          "title" => play.title,
          "code" => play.code,
          "historical_time" => "siglo_xvii",
          "historical_time_note" => "Contemporary. Reign of Philip IV."
        }
      })

      updated = Catalogue.get_play!(play.id)
      assert updated.historical_time == "siglo_xvii"
      assert updated.historical_time_note == "Contemporary. Reign of Philip IV."
    end

    test "saves a composition date", %{conn: conn} do
      conn = log_in_admin(conn)
      play = TestFixtures.play_fixture()

      {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/edit")

      view
      |> element("form[phx-submit]")
      |> render_submit(%{
        "play" => %{
          "title" => play.title,
          "code" => play.code,
          "composition_date_from" => "1606",
          "composition_date_to" => "1607",
          "composition_date_note" => "1606; 1607"
        }
      })

      updated = Catalogue.get_play!(play.id)
      assert updated.composition_date_from == 1606
      assert updated.composition_date_to == 1607
      assert updated.composition_date_note == "1606; 1607"
    end

    test "rejects a lone start year", %{conn: conn} do
      conn = log_in_admin(conn)
      play = TestFixtures.play_fixture()

      {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/edit")

      view
      |> element("form[phx-submit]")
      |> render_submit(%{
        "play" => %{
          "title" => play.title,
          "code" => play.code,
          "composition_date_from" => "1606"
        }
      })

      html = render(view)
      assert html =~ "must be given together with the end year"
    end

    test "renders the composition date inputs", %{conn: conn} do
      conn = log_in_admin(conn)
      play = TestFixtures.play_fixture()

      {:ok, _view, html} = live(conn, ~p"/admin/plays/#{play.id}/edit")

      assert html =~ ~s(name="play[composition_date_from]")
      assert html =~ ~s(name="play[composition_date_to]")
      assert html =~ ~s(name="play[composition_date_note]")
    end
  end
end
