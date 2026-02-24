defmodule EmotheWeb.LocaleControllerTest do
  use EmotheWeb.ConnCase, async: true

  test "POST /locale redirects to return_to path", %{conn: conn} do
    conn = post(conn, ~p"/locale", %{locale: "en", return_to: "/plays?search=hamlet"})

    assert redirected_to(conn) == "/plays?search=hamlet"
    assert get_session(conn, :locale) == "en"
  end

  test "POST /locale falls back to / when return_to missing", %{conn: conn} do
    conn = post(conn, ~p"/locale", %{locale: "en"})
    assert redirected_to(conn) == "/"
  end

  test "POST /locale rejects non-local return_to paths", %{conn: conn} do
    conn = post(conn, ~p"/locale", %{locale: "en", return_to: "https://evil.com"})
    assert redirected_to(conn) == "/"
  end

  test "POST /locale ignores invalid locale", %{conn: conn} do
    conn = post(conn, ~p"/locale", %{locale: "xx", return_to: "/plays"})
    assert redirected_to(conn) == "/plays"
    refute get_session(conn, :locale) == "xx"
  end
end
