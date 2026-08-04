defmodule Emothe.Places.Authority.Wikidata do
  @moduledoc """
  Wikidata over `req`. Two endpoints: `wbsearchentities` for the typeahead and
  `Special:EntityData/<id>.json` for the details.

  Nothing here is load-bearing for the app. A timeout or a 500 returns
  `{:error, :unavailable}`, the form says so inline, and every field stays typeable —
  a curator with no network can still do the whole job.
  """

  @behaviour Emothe.Places.Authority

  require Logger

  @search_url "https://www.wikidata.org/w/api.php"
  @entity_url "https://www.wikidata.org/wiki/Special:EntityData"
  @timeout 5_000

  # P31 "instance of" → our own vocabulary. Anything unlisted yields nil, which leaves
  # the curator to choose rather than guessing wrong.
  #
  # An entity carries *many* P31 claims and the useful one is rarely first: London leads
  # with metropolis, financial centre, and only then city. So `type_hint/1` scans the
  # whole list for the first claim this map knows, and a term earns its place here by
  # being a geographic feature class — `capital city` qualifies because a capital is
  # always at least a city, `tourist destination` and `college town` do not.
  @type_hints %{
    "Q515" => "city",
    "Q1549591" => "city",
    "Q200250" => "city",
    "Q5119" => "city",
    "Q902814" => "city",
    "Q3957" => "town",
    "Q6256" => "country",
    "Q5107" => "continent",
    "Q82794" => "region",
    "Q4022" => "river",
    "Q23397" => "lake",
    "Q165" => "sea",
    "Q23442" => "island",
    "Q8502" => "mountain",
    "Q4421" => "forest",
    "Q41176" => "building"
  }

  @impl true
  def search(term, opts \\ [])
  def search(term, _opts) when term in [nil, ""], do: {:ok, []}

  def search(term, opts) do
    params = [
      action: "wbsearchentities",
      search: term,
      language: opts[:locale] || "es",
      uselang: opts[:locale] || "es",
      type: "item",
      limit: 10,
      format: "json"
    ]

    case get(@search_url, [params: params] ++ req_opts(opts)) do
      {:ok, %{"search" => results}} when is_list(results) ->
        {:ok, Enum.map(results, &candidate/1)}

      {:ok, _other} ->
        {:error, :unexpected_response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def fetch(id), do: fetch(id, [])

  def fetch(id, opts) do
    case get("#{@entity_url}/#{id}.json", req_opts(opts)) do
      {:ok, %{"entities" => entities}} when is_map(entities) ->
        case Map.values(entities) do
          [entity | _] -> {:ok, details(entity, id)}
          [] -> {:error, :not_found}
        end

      {:ok, _other} ->
        {:error, :unexpected_response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp candidate(result) do
    %{
      id: result["id"],
      label: result["label"] || result["id"],
      description: result["description"]
    }
  end

  defp details(entity, id) do
    claims = entity["claims"] || %{}
    {latitude, longitude} = coordinates(claims)

    %{
      labels: labels(entity["labels"] || %{}),
      latitude: latitude,
      longitude: longitude,
      type_hint: type_hint(claims),
      parent: parent(claims),
      url: "https://www.wikidata.org/wiki/#{id}"
    }
  end

  defp labels(labels) do
    for {language, %{"value" => value}} <- labels,
        language in ~w(es en fr it pt ca),
        into: %{},
        do: {language, value}
  end

  defp coordinates(claims) do
    case entity_value(claims, "P625") do
      %{"latitude" => latitude, "longitude" => longitude} -> {latitude, longitude}
      _ -> {nil, nil}
    end
  end

  # The first claim we recognise, not the first claim. See the note on @type_hints.
  defp type_hint(claims) do
    claims
    |> entity_values("P31")
    |> Enum.find_value(fn %{"id" => qid} -> Map.get(@type_hints, qid) end)
  end

  # A place keeps every country it has ever belonged to, so London's P17 runs Roman
  # Empire, Kingdom of Mercia, …, United Kingdom — the current one last. Wikidata marks
  # the superseded ones with an end time (P582) and ranks the live one "preferred", so
  # drop the ended claims and take a preferred one if there is one. Falling back to the
  # unfiltered list keeps a place whose only claims are historical (a vanished polity)
  # from silently losing its parent.
  defp parent(claims) do
    live = claims |> entity_claims("P17") |> Enum.reject(&ended?/1)
    preferred = Enum.filter(live, &(&1["rank"] == "preferred"))

    case preferred ++ live ++ entity_claims(claims, "P17") do
      [claim | _] ->
        case claim_value(claim) do
          %{"id" => qid} -> %{id: qid, label: qid}
          _ -> nil
        end

      [] ->
        nil
    end
  end

  defp ended?(claim), do: Map.has_key?(claim["qualifiers"] || %{}, "P582")

  defp entity_claims(claims, property) do
    case claims[property] do
      list when is_list(list) -> Enum.reject(list, &(&1["rank"] == "deprecated"))
      _ -> []
    end
  end

  defp entity_values(claims, property) do
    claims |> entity_claims(property) |> Enum.flat_map(&List.wrap(claim_value(&1)))
  end

  defp claim_value(%{"mainsnak" => %{"datavalue" => %{"value" => value}}}), do: value
  defp claim_value(_), do: nil

  defp entity_value(claims, property) do
    claims |> entity_values(property) |> List.first()
  end

  defp req_opts(opts), do: Keyword.take(opts, [:plug])

  defp get(url, options) do
    # decode_body: false — Req infers the body format from the URL's own extension when
    # there's no content-type header (our entity URLs end in ".json"), so a non-200 with
    # a plain-text body ("not found") would otherwise fail Jason decoding *before* we get
    # to look at the status and come back as a generic decode error instead of :not_found.
    # Decoding it ourselves keeps status the first thing we branch on.
    [url: url, receive_timeout: @timeout, retry: false, decode_body: false]
    |> Keyword.merge(options)
    |> Req.new()
    |> Req.get()
    |> case do
      {:ok, %Req.Response{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
          _ -> {:error, :unexpected_response}
        end

      {:ok, %Req.Response{status: 404}} ->
        {:error, :not_found}

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("Wikidata returned #{status} for #{url}")
        {:error, :unavailable}

      {:error, reason} ->
        Logger.warning("Wikidata request failed: #{inspect(reason)}")
        {:error, :unavailable}
    end
  end
end
