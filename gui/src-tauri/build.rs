fn main() {
    // Log what assets are being embedded
    if let Ok(html) = std::fs::read_to_string("../dist/index.html") {
        if html.contains("placeholder") || html.contains("main.js") {
            println!("cargo:warning=ERROR: Embedding PLACEHOLDER assets from deps phase!");
        } else if html.contains("main-") {
            println!("cargo:warning=SUCCESS: Embedding real Vite bundle with hash");
        }
    }
    tauri_build::build()
}
