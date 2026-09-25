defmodule PlaycodeWeb.BrandingTest do
  @moduledoc """
  The application is Playcode; EMOTHE and ARTELOPE are the digital libraries it
  publishes. Chrome that names the application says Playcode, and copy that
  names the libraries keeps their brands. The UI renders in Spanish by default,
  so the assertions are in Spanish.
  """
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.TestFixtures

  test "the home page names the platform and the libraries it serves", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)
    page = LazyHTML.from_document(html)

    assert page |> LazyHTML.query("title") |> LazyHTML.text() =~ "Playcode"
    assert html =~ "La plataforma editorial de las bibliotecas digitales EMOTHE y ARTELOPE"
    # The navbar wordmark and the heading used to read EMOTHE.
    refute html =~ ~r/>\s*EMOTHE\s*</
    # The old subtitle expanded EMOTHE wrongly; it stands for "Early Modern
    # European Theatre: Heritage and Databases".
    refute html =~ "European Modernities"
  end

  test "the catalogue covers both collections", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/plays")

    assert has_element?(view, "h1", "Catálogo de obras")
    assert html =~ "de las colecciones EMOTHE y ARTELOPE"
    refute html =~ "Biblioteca Digital EMOTHE"
  end

  test "the login page names the platform", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/users/log-in")

    assert html =~ "Iniciar sesión en Playcode"
  end

  test "the accept-invite page welcomes the user to the platform", %{conn: conn} do
    {_user, token} = invited_user_fixture()

    {:ok, _view, html} = live(conn, ~p"/users/accept-invite/#{token}")

    assert html =~ "Bienvenido a Playcode"
  end

  test "pages carry the Playcode icon, not Phoenix's", %{conn: conn} do
    page = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert page |> LazyHTML.query(~s(link[rel="icon"][href^="/images/logo.svg"])) |> Enum.count() ==
             1

    # The opening path of the Phoenix bird that `mix phx.new` ships as logo.svg.
    refute File.read!("priv/static/images/logo.svg") =~ "m26.371 33.477"
  end
end
