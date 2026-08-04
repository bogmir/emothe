defmodule Emothe.Places.Authority do
  @moduledoc """
  A gazetteer authority: somewhere a place already has a stable identifier.

  Wikidata is the one that can be searched; GeoNames, Getty TGN and Pleiades are
  link-out targets until someone wants them. The behaviour exists because the seam was
  a requirement, and it has two implementations from day one — `Wikidata` and the
  `Stub` the test environment uses, which is what keeps the suite off the network.
  """

  alias Emothe.Places.Place

  @callback search(term :: String.t(), opts :: keyword()) ::
              {:ok, [%{id: String.t(), label: String.t(), description: String.t() | nil}]}
              | {:error, atom()}

  @callback fetch(id :: String.t()) ::
              {:ok,
               %{
                 labels: %{String.t() => String.t()},
                 latitude: float() | nil,
                 longitude: float() | nil,
                 type_hint: String.t() | nil,
                 parent: %{id: String.t(), label: String.t()} | nil,
                 url: String.t()
               }}
              | {:error, atom()}

  @registry %{
    "wikidata" => %{
      label: "Wikidata",
      url_pattern: "https://www.wikidata.org/wiki/~s",
      module: Emothe.Places.Authority.Wikidata
    },
    "geonames" => %{
      label: "GeoNames",
      url_pattern: "https://www.geonames.org/~s",
      module: nil
    },
    "tgn" => %{
      label: "Getty TGN",
      url_pattern: "https://vocab.getty.edu/page/tgn/~s",
      module: nil
    },
    "pleiades" => %{
      label: "Pleiades",
      url_pattern: "https://pleiades.stoa.org/places/~s",
      module: nil
    }
  }

  def registry do
    Enum.map(Place.authorities(), fn slug ->
      @registry |> Map.fetch!(slug) |> Map.put(:slug, slug)
    end)
  end

  @doc "The searchable implementation for the current environment."
  def impl do
    Application.get_env(:emothe, :place_authority, Emothe.Places.Authority.Wikidata)
  end

  @doc "The public page for a linked identifier, or nil when either half is missing."
  def url(slug, id) when is_binary(slug) and is_binary(id) do
    case Map.fetch(@registry, slug) do
      {:ok, %{url_pattern: pattern}} -> String.replace(pattern, "~s", id)
      :error -> nil
    end
  end

  def url(_slug, _id), do: nil

  def label(slug) do
    case Map.fetch(@registry, slug || "") do
      {:ok, %{label: label}} -> label
      :error -> ""
    end
  end
end
