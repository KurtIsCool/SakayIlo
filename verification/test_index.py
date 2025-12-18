from playwright.sync_api import sync_playwright

def verify_app():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()
        # Open local index.html using file protocol
        import os
        cwd = os.getcwd()
        page.goto(f"file://{cwd}/index.html")

        # Check title
        print(f"Page title: {page.title()}")

        # Check map element exists
        page.wait_for_selector("#map")

        # Check search button exists
        page.wait_for_selector("#search-btn")

        # Take screenshot
        screenshot_path = "verification/index_page.png"
        page.screenshot(path=screenshot_path)
        print(f"Screenshot saved to {screenshot_path}")

        browser.close()

if __name__ == "__main__":
    verify_app()
