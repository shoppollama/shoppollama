defmodule Shoppollama.Repo.Migrations.CreateProducts do
  use Ecto.Migration

  def change do
    create table(:products, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :stripe_product_id, :string, null: false
      add :name, :string, null: false
      add :description, :text
      add :price_cents, :integer, null: false
      add :currency, :string, default: "usd", null: false
      add :vendor, :string
      add :product_type, :string
      add :inventory, :integer, default: 0
      add :page_html, :text
      add :image_filename, :string
      add :image_content_type, :string
      add :image_data, :binary
      add :metadata, :map, default: %{}
      add :is_active, :boolean, default: true

      timestamps()
    end

    create unique_index(:products, [:stripe_product_id])
    create index(:products, [:name])
    create index(:products, [:product_type])
    create index(:products, [:is_active])
  end
end
