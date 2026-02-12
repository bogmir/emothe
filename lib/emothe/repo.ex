defmodule Emothe.Repo do
  use Ecto.Repo,
    otp_app: :emothe,
    adapter: Ecto.Adapters.Postgres
end
