let Uploaders = {}

Uploaders.S3 = function(entries, onViewError){
  entries.forEach(entry => {
    let formData = new FormData()
    let {url, fields} = entry.meta
    Object.entries(fields).forEach(([key, val]) => {
      formData.append(key, val)
      console.log(`Adding field: ${key} = ${val}`)
    })
    formData.append("file", entry.file)
    
    // Debug: Log the form data
    console.log("Upload URL:", url)
    console.log("File:", entry.file)
    console.log("Form fields:", fields)
    
    let xhr = new XMLHttpRequest()
    onViewError(() => xhr.abort())
    xhr.onload = () => {
      console.log("Upload response status:", xhr.status)
      console.log("Upload response text:", xhr.responseText)
      if(xhr.status === 204) {
        entry.progress(100)
      } else {
        console.error("Upload failed with status:", xhr.status)
        entry.error()
      }
    }
    xhr.onerror = (error) => {
      console.error("Upload error:", error)
      entry.error()
    }
    xhr.upload.addEventListener("progress", (event) => {
      if(event.lengthComputable){
        let percent = Math.round((event.loaded / event.total) * 100)
        if(percent < 100){ entry.progress(percent) }
      }
    })

    xhr.open("POST", url, true)
    console.log("Sending request to:", url)
    xhr.send(formData)
  })
}

export default Uploaders;