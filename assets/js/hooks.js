// LiveView Hooks for Shoppollama

// ChatScroll hook - handles auto-scrolling to bottom of chat messages
const ChatScroll = {
  mounted() {
    this.scrollToBottom()
  },
  
  updated() {
    this.scrollToBottom()
  },
  
  scrollToBottom() {
    this.el.scrollTop = this.el.scrollHeight
  }
}

// AutoFocus hook - automatically focuses input elements
const AutoFocus = {
  mounted() {
    this.el.focus()
  },
  
  updated() {
    this.el.focus()
  }
}

// MessagePreserver hook - preserves message state during updates
const MessagePreserver = {
  mounted() {
    // Store initial content
    this.originalContent = this.el.innerHTML
  },
  
  beforeUpdate() {
    // Preserve scroll position if needed
    const container = document.getElementById('messages-container')
    if (container) {
      this.wasAtBottom = container.scrollTop >= (container.scrollHeight - container.clientHeight - 10)
    }
  },
  
  updated() {
    // Restore scroll position if user was at bottom
    if (this.wasAtBottom) {
      const container = document.getElementById('messages-container')
      if (container) {
        container.scrollTop = container.scrollHeight
      }
    }
  }
}

export { ChatScroll, AutoFocus, MessagePreserver }