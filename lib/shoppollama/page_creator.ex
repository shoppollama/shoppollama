defmodule Shoppollama.PageCreator do
  @moduledoc """
  Handles creation and retrieval of product page HTML
  """

  require Logger
  alias Shoppollama.StripeProductClient

  @doc """
  Generates HTML for a product page based on Stripe product ID
  """
  def get_page_html(stripe_product_id) do
    case StripeProductClient.get_product(stripe_product_id) do
      {:ok, product_data} ->
        # Try to get the product from local database to get the image_url
        local_product = case Shoppollama.Repo.get_by(Shoppollama.Product, stripe_product_id: stripe_product_id) do
          nil -> nil
          product -> product
        end
        
        # Merge the image_url from local database if available
        product_data_with_image = case local_product do
          nil -> product_data
          product -> 
            if product.image_url do
              Map.put(product_data, :image_url, product.image_url)
            else
              product_data
            end
        end
        
        html = generate_product_page_html(product_data_with_image)
        {:ok, html}

      {:error, reason} ->
        Logger.error("Failed to get product for page generation: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Generates HTML content for a product page (Bandcamp-style dark theme)
  """
  def generate_product_page_html(product_data) do
    price_display = case product_data.price do
      nil -> "Contact for pricing"
      price when is_number(price) -> "$#{:erlang.float_to_binary(price / 1, [{:decimals, 2}])}"
      price -> "$#{price}"
    end

    cover_image = case Map.get(product_data, :image_url) do
      nil -> "/images/default-product.png"
      "" -> "/images/default-product.png"
      url -> url
    end

    # Get payment link from product metadata or fallback to Stripe dashboard
    payment_url = case Map.get(product_data, :payment_link_url) do
      nil -> "https://dashboard.stripe.com/products/#{product_data.id}"
      "" -> "https://dashboard.stripe.com/products/#{product_data.id}"
      url -> url
    end

    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>#{product_data.title || "Product"} | ShoppOllama</title>
        <style>
            * { box-sizing: border-box; margin: 0; padding: 0; }
            body {
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                background-color: #1a1a1a;
                color: #fff;
                min-height: 100vh;
            }
            
            /* Header */
            .header {
                background-color: #333;
                padding: 12px 16px;
                display: flex;
                justify-content: space-between;
                align-items: center;
            }
            .logo {
                font-size: 1.25rem;
                font-weight: bold;
                color: #fff;
                text-decoration: none;
            }
            .logo span { color: #1da0c3; }
            
            /* Artist Bar */
            .artist-bar {
                background-color: #2a2a2a;
                padding: 12px 16px;
                display: flex;
                align-items: center;
                gap: 12px;
            }
            .artist-avatar {
                width: 40px;
                height: 40px;
                border-radius: 50%;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                display: flex;
                align-items: center;
                justify-content: center;
                font-weight: bold;
                font-size: 1rem;
            }
            .artist-info { flex: 1; }
            .artist-name { font-weight: 600; font-size: 0.95rem; }
            .artist-location { color: #888; font-size: 0.8rem; }
            .follow-btn {
                color: #1da0c3;
                font-size: 0.85rem;
                text-decoration: none;
            }
            
            /* Hero Image */
            .hero-image {
                width: 100%;
                aspect-ratio: 1;
                object-fit: cover;
                display: block;
            }
            
            /* Carousel Dots */
            .carousel-dots {
                display: flex;
                justify-content: center;
                gap: 8px;
                padding: 16px;
                background-color: #1a1a1a;
            }
            .dot {
                width: 8px;
                height: 8px;
                border-radius: 50%;
                background-color: #555;
            }
            .dot.active { background-color: #fff; }
            
            /* Product Info */
            .product-info {
                padding: 20px 16px;
                display: flex;
                align-items: center;
                gap: 16px;
            }
            .play-button {
                width: 56px;
                height: 56px;
                border-radius: 50%;
                background-color: #333;
                border: 2px solid #555;
                display: flex;
                align-items: center;
                justify-content: center;
                cursor: pointer;
            }
            .play-icon {
                width: 0;
                height: 0;
                border-left: 16px solid #fff;
                border-top: 10px solid transparent;
                border-bottom: 10px solid transparent;
                margin-left: 4px;
            }
            .product-details { flex: 1; }
            .product-title {
                font-size: 1.1rem;
                font-weight: 600;
                margin-bottom: 4px;
            }
            .product-price-tag {
                display: inline-block;
                background-color: #333;
                border: 1px solid #555;
                padding: 2px 8px;
                border-radius: 4px;
                font-size: 0.75rem;
                margin-left: 8px;
            }
            .product-artist {
                color: #888;
                font-size: 0.85rem;
            }
            .product-meta {
                color: #666;
                font-size: 0.8rem;
                margin-top: 2px;
            }
            
            /* Purchase Button */
            .purchase-btn {
                display: block;
                width: calc(100% - 32px);
                margin: 8px 16px 16px;
                padding: 14px;
                background-color: #1da0c3;
                color: #fff;
                border: none;
                border-radius: 4px;
                font-size: 1rem;
                font-weight: 600;
                cursor: pointer;
                text-align: center;
                text-decoration: none;
            }
            .purchase-btn:hover { background-color: #1789a8; }
            
            /* Action Buttons */
            .action-buttons {
                display: flex;
                justify-content: center;
                gap: 48px;
                padding: 16px;
                border-bottom: 1px solid #333;
            }
            .action-btn {
                display: flex;
                align-items: center;
                gap: 8px;
                color: #888;
                font-size: 0.9rem;
                background: none;
                border: none;
                cursor: pointer;
            }
            .action-btn:hover { color: #fff; }
            
            /* Description */
            .description {
                padding: 20px 16px;
                color: #ccc;
                font-size: 0.9rem;
                line-height: 1.6;
            }
            
            /* Progress Bar */
            .progress-container {
                display: flex;
                align-items: center;
                gap: 12px;
                padding: 12px 16px;
                cursor: pointer;
            }
            .progress-time {
                font-size: 0.75rem;
                color: #888;
                min-width: 40px;
            }
            .progress-bar {
                flex: 1;
                height: 4px;
                background-color: #444;
                border-radius: 2px;
                position: relative;
            }
            .progress-fill {
                height: 100%;
                background-color: #1da0c3;
                border-radius: 2px;
                width: 0%;
                transition: width 0.1s;
            }
            .progress-handle {
                width: 12px;
                height: 12px;
                background-color: #fff;
                border-radius: 50%;
                position: absolute;
                top: 50%;
                transform: translate(-50%, -50%);
                left: 0%;
                box-shadow: 0 2px 4px rgba(0,0,0,0.3);
            }
            
            /* Play button states */
            .play-button.playing .play-icon {
                border-left: none;
                width: 16px;
                height: 16px;
                border-top: none;
                border-bottom: none;
                background: linear-gradient(to right, #fff 0%, #fff 35%, transparent 35%, transparent 65%, #fff 65%, #fff 100%);
            }
            
            /* Footer */
            .footer {
                padding: 20px 16px;
                text-align: center;
                color: #666;
                font-size: 0.75rem;
                position: fixed;
                bottom: 0;
                left: 0;
                right: 0;
                background-color: #1a1a1a;
            }
            .footer a { color: #1da0c3; text-decoration: none; }
            
            /* Add padding at bottom for fixed footer */
            body { padding-bottom: 60px; }
        </style>
    </head>
    <body>
        <!-- Artist Bar -->
        <div class="artist-bar">
            <div class="artist-avatar">S</div>
            <div class="artist-info">
                <div class="artist-name">shoppollama</div>
                <div class="artist-location">Online Store</div>
            </div>
            <a href="/" class="follow-btn">visit store</a>
        </div>
        
        <!-- Hero Image -->
        <img src="#{cover_image}" alt="#{product_data.title}" class="hero-image" />
        
        <!-- Audio Player (hidden) -->
        <audio id="audio-player" src="/images/demo-v4.mp3" preload="metadata"></audio>
        
        <!-- Product Info -->
        <div class="product-info">
            <div class="play-button" id="play-btn" onclick="togglePlay()">
                <div class="play-icon" id="play-icon"></div>
            </div>
            <div class="product-details">
                <div class="product-title">
                    #{product_data.title}
                    <span class="product-price-tag">#{price_display}</span>
                </div>
                <div class="product-artist">by ShoppOllama</div>
                <div class="product-meta">Digital Product</div>
            </div>
        </div>
        
        <!-- Progress Bar -->
        <div class="progress-container" onclick="seek(event)">
            <div class="progress-time" id="current-time">00:00</div>
            <div class="progress-bar">
                <div class="progress-fill" id="progress-fill"></div>
                <div class="progress-handle" id="progress-handle"></div>
            </div>
            <div class="progress-time" id="duration">00:00</div>
        </div>
        
        <!-- Purchase Button -->
        <a href="#{payment_url}" target="_blank" class="purchase-btn">
            Buy Now
        </a>
        
        <!-- Description -->
        <div class="description">
            #{product_data.description || ""}
        </div>
        
        <!-- Footer -->
        <div class="footer">
            Powered by <a href="https://github.com/shoppollama/shoppollama?ref=app" target="_blank">shoppollama</a>
        </div>
        
        <script>
            const audio = document.getElementById('audio-player');
            const playBtn = document.getElementById('play-btn');
            const playIcon = document.getElementById('play-icon');
            const progressFill = document.getElementById('progress-fill');
            const progressHandle = document.getElementById('progress-handle');
            const currentTimeEl = document.getElementById('current-time');
            const durationEl = document.getElementById('duration');
            
            function formatTime(seconds) {
                const mins = Math.floor(seconds / 60);
                const secs = Math.floor(seconds % 60);
                return mins.toString().padStart(2, '0') + ':' + secs.toString().padStart(2, '0');
            }
            
            function togglePlay() {
                if (audio.paused) {
                    audio.play();
                    playBtn.classList.add('playing');
                } else {
                    audio.pause();
                    playBtn.classList.remove('playing');
                }
            }
            
            audio.addEventListener('loadedmetadata', () => {
                durationEl.textContent = formatTime(audio.duration);
            });
            
            audio.addEventListener('timeupdate', () => {
                const percent = (audio.currentTime / audio.duration) * 100;
                progressFill.style.width = percent + '%';
                progressHandle.style.left = percent + '%';
                currentTimeEl.textContent = formatTime(audio.currentTime);
            });
            
            audio.addEventListener('ended', () => {
                playBtn.classList.remove('playing');
                progressFill.style.width = '0%';
                progressHandle.style.left = '0%';
            });
            
            function seek(event) {
                const progressBar = document.querySelector('.progress-bar');
                const rect = progressBar.getBoundingClientRect();
                const percent = (event.clientX - rect.left) / rect.width;
                audio.currentTime = percent * audio.duration;
            }
        </script>
    </body>
    </html>
    """
  end
end
