defmodule Emothe.Repo.Migrations.AddDeviceInfoToUsersTokens do
  use Ecto.Migration

  def change do
    alter table(:users_tokens) do
      add :ip_address, :string
      add :user_agent, :string
    end
  end
end
