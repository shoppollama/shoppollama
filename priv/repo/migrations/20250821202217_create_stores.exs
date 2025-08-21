defmodule Shoppollama.Repo.Migrations.CreateStores do
  use Ecto.Migration

  def change do
    create table(:stores) do
      add :shop_domain, :string, null: false
      add :access_token, :string, null: false
      add :shop_name, :string
      add :is_active, :boolean, default: true, null: false

      timestamps()
    end

    create unique_index(:stores, [:shop_domain])
  end
end
