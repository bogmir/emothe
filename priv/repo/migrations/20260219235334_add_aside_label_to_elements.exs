defmodule Emothe.Repo.Migrations.AddAsideLabelToElements do
  use Ecto.Migration

  def change do
    alter table(:play_elements) do
      add :aside_label, :text
    end
  end
end
