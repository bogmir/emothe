defmodule EmotheWeb.RateLimit do
  @moduledoc """
  Simple sliding-window rate limiter backed by ETS.

  Best-effort (not perfectly atomic under concurrent load), which is
  acceptable for auth-endpoint protection — the goal is blocking bots,
  not enforcing a hard cap to the exact request.

  The ETS table `:emothe_rate_limit` must be created before this module is
  used; it is started in `Emothe.Application.start/2`.
  """

  @table :emothe_rate_limit

  @doc """
  Checks the rate for `key`.

  Returns `:ok` if under the limit, or `{:error, :rate_limited}` if the
  limit has been reached within the current window.

  - `limit` — max requests allowed per window
  - `window_ms` — window size in milliseconds
  """
  @spec check_rate(String.t(), pos_integer(), pos_integer()) ::
          :ok | {:error, :rate_limited}
  def check_rate(key, limit, window_ms) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, key) do
      [{^key, count, window_start}] when now - window_start < window_ms ->
        if count >= limit do
          {:error, :rate_limited}
        else
          :ets.update_counter(@table, key, {2, 1})
          :ok
        end

      _ ->
        :ets.insert(@table, {key, 1, now})
        :ok
    end
  end
end
