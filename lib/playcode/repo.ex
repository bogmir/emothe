defmodule Playcode.Repo do
  use Ecto.Repo,
    otp_app: :playcode,
    adapter: Ecto.Adapters.Postgres
end
