defmodule Emothe.Places.Authority.WikidataTest do
  use ExUnit.Case, async: true

  alias Emothe.Places.Authority
  alias Emothe.Places.Authority.Wikidata

  defp json(name), do: File.read!("test/fixtures/wikidata/#{name}.json") |> Jason.decode!()

  # Req 0.5's `run_plug` treats a 2-tuple `{module, opts}` as a *named* stub lookup
  # (`Req.Test.stub/2` registry), not a literal plug — so `{Req.Test, fun}` fails with
  # "cannot find mock/stub". A bare `fun/1` matches the direct-function-plug clause and
  # runs inline, no registry involved, which is what keeps this deterministic and
  # process-local.
  defp stub(body) do
    fn conn ->
      Req.Test.json(conn, body)
    end
  end

  describe "search/2" do
    test "returns id, label and description per candidate" do
      assert {:ok, [first, second]} =
               Wikidata.search("Roma", plug: stub(json("search_roma")))

      assert first == %{id: "Q220", label: "Rome", description: "capital city of Italy"}
      assert second.id == "Q2634"
    end

    test "a blank term makes no request" do
      assert {:ok, []} = Wikidata.search("", plug: stub(%{}))
    end

    test "a transport failure is an :unavailable error, never a crash" do
      plug = fn conn -> Req.Test.transport_error(conn, :timeout) end
      assert {:error, :unavailable} = Wikidata.search("Roma", plug: plug)
    end
  end

  describe "fetch/2" do
    test "extracts labels, coordinates, a type hint and the parent" do
      assert {:ok, details} = Wikidata.fetch("Q220", plug: stub(json("Q220")))

      assert details.labels["es"] == "Roma"
      assert details.labels["en"] == "Rome"
      assert details.latitude == 41.9028
      assert details.longitude == 12.4964
      assert details.type_hint == "city"
      assert details.parent == %{id: "Q38", label: "Q38"}
      assert details.url == "https://www.wikidata.org/wiki/Q220"
    end

    test "an entity with no coordinates yields nil rather than failing" do
      body = %{
        "entities" => %{
          "Q1" => %{
            "id" => "Q1",
            "labels" => %{"es" => %{"value" => "Atlántida"}},
            "claims" => %{}
          }
        }
      }

      assert {:ok, details} = Wikidata.fetch("Q1", plug: stub(body))
      assert details.latitude == nil
      assert details.type_hint == nil
      assert details.parent == nil
      assert details.labels["es"] == "Atlántida"
    end

    test "a malformed body is an error, not a match failure" do
      assert {:error, :unexpected_response} =
               Wikidata.fetch("Q220", plug: stub(%{"oops" => true}))
    end

    test "a 404 is an error" do
      plug = fn conn -> Plug.Conn.send_resp(conn, 404, "not found") end
      assert {:error, :not_found} = Wikidata.fetch("Q999999999", plug: plug)
    end
  end

  describe "the registry" do
    test "lists every authority slug the schema allows" do
      slugs = Enum.map(Authority.registry(), & &1.slug)
      assert Enum.sort(slugs) == Enum.sort(Emothe.Places.Place.authorities())
    end

    test "builds an outbound URL for a linked place" do
      assert Authority.url("wikidata", "Q220") == "https://www.wikidata.org/wiki/Q220"
      assert Authority.url("geonames", "3169070") == "https://www.geonames.org/3169070"
      assert Authority.url("wikidata", nil) == nil
      assert Authority.url(nil, "Q220") == nil
    end

    test "the test environment uses the stub, so nothing calls out" do
      assert Authority.impl() == Emothe.Places.Authority.Stub
    end
  end
end
