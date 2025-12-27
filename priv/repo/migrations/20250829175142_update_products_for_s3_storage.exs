defmodule Shoppollama.Repo.Migrations.UpdateProductsForS3Storage do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :image_url, :string
      remove :image_data
    end
  end
end
