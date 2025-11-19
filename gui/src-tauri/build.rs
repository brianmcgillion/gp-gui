// Tauri build script
//
// IMPORTANT: This build script requires the frontend to be built BEFORE
// any Rust compilation happens (cargo check, build, clippy, test).
//
// The frontend assets (../dist) are embedded into the binary at build time.
// If the dist directory doesn't exist, the build will fail with:
//   "The frontendDist configuration is set to ../dist but this path doesn't exist"
//
// To build the frontend:
//   cd gui && npm install && npm run build
//
// This is required in CI/CD pipelines - see GitHub Actions workflows for examples.

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
