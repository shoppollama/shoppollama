defmodule Shoppollama.Product do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "products" do
    field :stripe_product_id, :string
    field :name, :string
    field :description, :string
    field :price_cents, :integer
    field :currency, :string, default: "usd"
    field :vendor, :string
    field :product_type, :string
    field :inventory, :integer, default: 0
    field :page_html, :string
    field :image_filename, :string
    field :image_content_type, :string
    field :image_url, :string
    field :metadata, :map, default: %{}
    field :is_active, :boolean, default: true

    timestamps()
  end

  @doc false
  def changeset(product, attrs) do
    product
    |> cast(attrs, [
      :stripe_product_id,
      :name,
      :description,
      :price_cents,
      :currency,
      :vendor,
      :product_type,
      :inventory,
      :page_html,
      :image_filename,
      :image_content_type,
      :image_url,
      :metadata,
      :is_active
    ])
    |> validate_required([:stripe_product_id, :name, :price_cents])
    |> validate_number(:price_cents, greater_than: 0)
    |> validate_number(:inventory, greater_than_or_equal_to: 0)
    |> unique_constraint(:stripe_product_id)
    |> validate_image_content_type()
  end

  @doc false
  def image_changeset(product, attrs) do
    product
    |> cast(attrs, [:image_filename, :image_content_type, :image_url])
    |> validate_required([:image_filename, :image_content_type, :image_url])
    |> validate_length(:image_filename, max: 255)
    |> validate_inclusion(:image_content_type, ["image/jpeg", "image/png", "image/gif", "image/webp"])
    |> validate_format(:image_url, ~r/^https?:\/\/.+/, message: "must be a valid URL")
  end

  defp validate_image_content_type(changeset) do
    case get_field(changeset, :image_content_type) do
      nil -> changeset
      content_type ->
        if content_type in ["image/jpeg", "image/png", "image/gif", "image/webp"] do
          changeset
        else
          add_error(changeset, :image_content_type, "must be a valid image format (JPEG, PNG, GIF, WebP)")
        end
    end
  end

  @doc """
  Returns the image URL for serving the product image
  """
  def image_url(%__MODULE__{image_url: url}) when not is_nil(url) do
    url
  end
  def image_url(_), do: "/images/placeholder.jpg"

  @doc """
  Returns the formatted price as a string
  """
  def formatted_price(%__MODULE__{price_cents: price_cents, currency: currency}) do
    case currency do
      "usd" -> "$#{price_cents / 100}"
      _ -> "#{price_cents / 100} #{String.upcase(currency)}"
    end
  end
end