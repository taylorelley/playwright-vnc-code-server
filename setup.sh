#!/usr/bin/env bash

#==============================================================================
# Complete Playwright VNC Development Environment Setup
# For fresh Ubuntu/Debian installations
#
# What this creates:
# - Stable VNC server (Xvfb + x11vnc) accessible via web browser
# - VS Code in browser (code-server) for development
# - Complete Playwright testing environment
# - Auto-starting services
#
# Access URLs after setup:
# - http://localhost:8080 - VS Code (code-server)
# - http://localhost:6080 - VNC Desktop (noVNC)
# - localhost:5901 - VNC Direct connection
# Password: vscode
#==============================================================================

set -e  # Exit on any error

# Configuration
VNC_PORT=${1:-5901}
NOVNC_PORT=${2:-6080}
CODESERVER_PORT=${3:-8080}
VNC_PASSWORD=${4:-"vscode"}
NODE_VERSION=${5:-"18"}
DISABLE_CODESERVER_AUTH=${6:-"false"}
DISABLE_VNC_AUTH=${7:-"false"}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root"
    echo "Usage: sudo $0 [vnc_port] [novnc_port] [codeserver_port] [password] [node_version] [disable_codeserver_auth] [disable_vnc_auth]"
    echo "Example: sudo $0 5901 6080 8080 mypassword 18 false false"
    echo "Example: sudo $0 5901 6080 8080 mypassword 18 true true  # No passwords"
    echo ""
    echo "Parameters:"
    echo "  vnc_port              - VNC server port (default: 5901)"
    echo "  novnc_port            - noVNC web port (default: 6080)"
    echo "  codeserver_port       - VS Code server port (default: 8080)"
    echo "  password              - Password for services (default: vscode)"
    echo "  node_version          - Node.js version (default: 18)"
    echo "  disable_codeserver_auth - true/false to disable VS Code auth (default: false)"
    echo "  disable_vnc_auth      - true/false to disable VNC auth (default: false)"
    exit 1
fi

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    OS_VERSION=$VERSION_ID
else
    log_error "Cannot detect OS version"
    exit 1
fi

log_info "Detected OS: $OS $OS_VERSION"

# Validate OS
if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
    log_error "This script supports Ubuntu and Debian only"
    exit 1
fi

echo ""
echo "=================================================================="
echo "🎭 Playwright VNC Development Environment Setup"
echo "=================================================================="
echo "VNC Port: $VNC_PORT"
echo "noVNC Port: $NOVNC_PORT"
echo "code-server Port: $CODESERVER_PORT"
echo "Password: $VNC_PASSWORD"
echo "Node.js Version: $NODE_VERSION"
echo "code-server Auth: $([ "$DISABLE_CODESERVER_AUTH" = "true" ] && echo "DISABLED" || echo "ENABLED")"
echo "VNC Auth: $([ "$DISABLE_VNC_AUTH" = "true" ] && echo "DISABLED" || echo "ENABLED")"
echo "Resolution: 1920x1080"
echo "=================================================================="
echo ""

read -p "Continue with installation? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Installation cancelled"
    exit 0
fi

#==============================================================================
# STEP 1: System Updates and Basic Packages
#==============================================================================
log_info "Step 1: Updating system and installing basic packages..."

# Update package lists
apt-get update

# Install essential packages
apt-get install -y \
    curl \
    wget \
    unzip \
    sudo \
    systemd \
    dbus \
    ca-certificates \
    gnupg \
    lsb-release \
    software-properties-common \
    apt-transport-https

log_success "System updated and basic packages installed"

#==============================================================================
# STEP 2: VNC and X11 Components
#==============================================================================
log_info "Step 2: Installing VNC and X11 components..."

apt-get install -y \
    xvfb \
    x11vnc \
    xterm \
    x11-utils \
    x11-xserver-utils \
    xauth \
    python3 \
    python3-pip \
    python3-numpy

log_success "VNC and X11 components installed"

#==============================================================================
# STEP 3: Install Node.js
#==============================================================================
log_info "Step 3: Installing Node.js $NODE_VERSION..."

# Add NodeSource repository
curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash -

# Install Node.js
apt-get install -y nodejs

# Verify installation
NODE_INSTALLED_VERSION=$(node --version)
NPM_INSTALLED_VERSION=$(npm --version)
log_success "Node.js installed: $NODE_INSTALLED_VERSION"
log_success "NPM installed: $NPM_INSTALLED_VERSION"

#==============================================================================
# STEP 4: Install code-server
#==============================================================================
log_info "Step 4: Installing code-server..."

curl -fsSL https://code-server.dev/install.sh | sh

# Verify installation
CODESERVER_VERSION=$(code-server --version | head -n1)
log_success "code-server installed: $CODESERVER_VERSION"

#==============================================================================
# STEP 5: Install and Setup noVNC
#==============================================================================
log_info "Step 5: Installing noVNC..."

# Create noVNC directory
mkdir -p /usr/local/novnc
cd /tmp

# Download noVNC
if curl -sSL https://github.com/novnc/noVNC/archive/v1.2.0.zip -o novnc.zip; then
    unzip -q novnc.zip -d /usr/local/novnc/
    cp /usr/local/novnc/noVNC-1.2.0/vnc.html /usr/local/novnc/noVNC-1.2.0/index.html
    log_success "noVNC downloaded and configured"
else
    log_error "Failed to download noVNC"
    exit 1
fi

# Download websockify
if curl -sSL https://github.com/novnc/websockify/archive/v0.10.0.zip -o websockify.zip; then
    unzip -q websockify.zip -d /usr/local/novnc/
    ln -sf /usr/local/novnc/websockify-0.10.0 /usr/local/novnc/noVNC-1.2.0/utils/websockify
    
    # Fix python shebang
    sed -i -E 's/^python /python3 /' /usr/local/novnc/websockify-0.10.0/run
    
    # Make executable
    chmod +x /usr/local/novnc/noVNC-1.2.0/utils/launch.sh
    chmod +x /usr/local/novnc/websockify-0.10.0/run
    
    log_success "websockify installed and configured"
else
    log_error "Failed to download websockify"
    exit 1
fi

# Cleanup
rm -f /tmp/novnc.zip /tmp/websockify.zip

#==============================================================================
# STEP 6: Install Playwright
#==============================================================================
log_info "Step 6: Installing Playwright and browsers..."

# Create workspace directory
mkdir -p /root/workspace
cd /root/workspace

# Initialize npm project
npm init -y >/dev/null 2>&1

# Install Playwright
npm install -D @playwright/test

# Install Playwright browsers
npx playwright install

# Install system dependencies for browsers
npx playwright install-deps

log_success "Playwright and browsers installed"

#==============================================================================
# STEP 7: Setup VNC Environment
#==============================================================================
log_info "Step 7: Setting up VNC environment..."

# Find free display number
DISPLAY_NUM=1
for i in {1..20}; do
    if [ ! -f "/tmp/.X${i}-lock" ] && \
       [ ! -S "/tmp/.X11-unix/X${i}" ] && \
       ! netstat -x 2>/dev/null | grep -q "X${i}" && \
       ! pgrep -f ":${i}" >/dev/null; then
        DISPLAY_NUM=$i
        break
    fi
done

log_info "Using display :$DISPLAY_NUM"

# Create VNC directory and password
mkdir -p /root/.vnc

if [ "$DISABLE_VNC_AUTH" = "true" ]; then
    log_info "VNC authentication disabled - no password required"
    echo "" > /root/.vnc/passwd.txt
    chmod 600 /root/.vnc/passwd.txt
else
    echo "$VNC_PASSWORD" > /root/.vnc/passwd.txt
    chmod 600 /root/.vnc/passwd.txt
    log_info "VNC password set to: $VNC_PASSWORD"
fi

# Create VNC startup script
cat > /usr/local/bin/start-vnc-server << VNC_SCRIPT
#!/bin/bash

# Allow overriding via environment but fall back to install-time defaults
DISPLAY_NUM=\${DISPLAY_NUM:-$DISPLAY_NUM}
VNC_PORT=\${VNC_PORT:-$VNC_PORT}
export DISPLAY=:\${DISPLAY_NUM}

echo "Starting VNC server on display :\$DISPLAY_NUM"

# Kill any existing processes
pkill -f "Xvfb.*:\$DISPLAY_NUM" 2>/dev/null || true
pkill -f "x11vnc.*:\$DISPLAY_NUM" 2>/dev/null || true
sleep 2

# Remove display files
rm -rf /tmp/.X11-unix/X\$DISPLAY_NUM /tmp/.X\$DISPLAY_NUM-lock

# Start Xvfb
echo "\$(date): Starting Xvfb on display :\$DISPLAY_NUM"
Xvfb :\$DISPLAY_NUM -screen 0 1920x1080x24 -ac +extension GLX +render -noreset > /tmp/xvfb.log 2>&1 &
XVFB_PID=\$!

# Wait for Xvfb
sleep 3

# Verify Xvfb
if ! kill -0 \$XVFB_PID 2>/dev/null; then
    echo "ERROR: Xvfb failed to start"
    cat /tmp/xvfb.log
    exit 1
fi

# Test X11 connection
if ! DISPLAY=:\$DISPLAY_NUM xdpyinfo >/dev/null 2>&1; then
    echo "ERROR: X11 display not accessible"
    kill \$XVFB_PID
    exit 1
fi

echo "\$(date): Xvfb started successfully (PID: \$XVFB_PID)"

# Start simple window manager (xterm)
echo "\$(date): Starting xterm window manager"
DISPLAY=:\$DISPLAY_NUM xterm -geometry 120x40+10+10 -title "Playwright VNC Desktop - 1920x1080" > /tmp/xterm.log 2>&1 &

# Start x11vnc with conditional authentication
echo "\$(date): Starting x11vnc"
if [ "$DISABLE_VNC_AUTH" = "true" ]; then
    # No authentication
    x11vnc -display :\$DISPLAY_NUM \\
        -rfbport \$VNC_PORT \\
        -localhost \\
        -shared \\
        -forever \\
        -nopw \\
        -quiet \\
        -bg \\
        -xkb \\
        -noxrecord \\
        -noxfixes \\
        -noxdamage
else
    # With password authentication
    x11vnc -display :\$DISPLAY_NUM \\
        -rfbport \$VNC_PORT \\
        -localhost \\
        -passwd $VNC_PASSWORD \\
        -shared \\
        -forever \\
        -nopw \\
        -quiet \\
        -bg \\
        -xkb \\
        -noxrecord \\
        -noxfixes \\
        -noxdamage
fi

# Wait for x11vnc
sleep 2

# Verify x11vnc
if ! pgrep -f "x11vnc.*:\$DISPLAY_NUM" >/dev/null; then
    echo "ERROR: x11vnc failed to start"
    kill \$XVFB_PID
    exit 1
fi

# Verify port listening
if ! netstat -tulpn | grep ":\$VNC_PORT " >/dev/null; then
    echo "ERROR: VNC not listening on port \$VNC_PORT"
    kill \$XVFB_PID
    pkill -f "x11vnc.*:\$DISPLAY_NUM"
    exit 1
fi

echo "\$(date): VNC server ready on port \$VNC_PORT"

# Monitor processes
while true; do
    if ! kill -0 \$XVFB_PID 2>/dev/null; then
        echo "\$(date): Xvfb died, restarting service"
        exit 1
    fi
    
    if ! pgrep -f "x11vnc.*:\$DISPLAY_NUM" >/dev/null; then
        echo "\$(date): x11vnc died, restarting service"
        exit 1
    fi
    
    sleep 30
done
VNC_SCRIPT

chmod +x /usr/local/bin/start-vnc-server

log_success "VNC startup script created"

#==============================================================================
# STEP 8: Setup code-server
#==============================================================================
log_info "Step 8: Setting up code-server..."

# Create code-server config
mkdir -p /root/.config/code-server

if [ "$DISABLE_CODESERVER_AUTH" = "true" ]; then
    cat > /root/.config/code-server/config.yaml << CODESERVER_CONFIG_NOAUTH
bind-addr: 0.0.0.0:$CODESERVER_PORT
auth: none
cert: false
disable-telemetry: true
disable-update-check: true
CODESERVER_CONFIG_NOAUTH
    log_info "code-server configured with no authentication"
else
    cat > /root/.config/code-server/config.yaml << CODESERVER_CONFIG_AUTH
bind-addr: 0.0.0.0:$CODESERVER_PORT
auth: password
password: $VNC_PASSWORD
cert: false
disable-telemetry: true
disable-update-check: true
CODESERVER_CONFIG_AUTH
    log_info "code-server configured with password authentication"
fi

log_success "code-server configured"

#==============================================================================
# STEP 9: Create Workspace and Playwright Configuration
#==============================================================================
log_info "Step 9: Setting up Playwright workspace..."

cd /root/workspace

# Create Playwright configuration
cat > playwright.config.js << 'PLAYWRIGHT_CONFIG'
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: [
    ['html', { open: 'never' }],
    ['list']
  ],
  
  use: {
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
    headless: false,
    slowMo: 200,
  },

  projects: [
    {
      name: 'chromium',
      use: { 
        ...devices['Desktop Chrome'],
        launchOptions: {
                      args: [
            '--no-sandbox',
            '--disable-setuid-sandbox',
            '--disable-dev-shm-usage',
            '--disable-gpu',
            '--window-size=1200,800',
            '--window-position=50,50'
          ]
        }
      },
    },
    {
      name: 'firefox',
      use: { 
        ...devices['Desktop Firefox'],
        launchOptions: {
          firefoxUserPrefs: {
            'media.navigator.streams.fake': true,
            'media.navigator.permission.disabled': true,
          }
        }
      },
    },
  ],
});
PLAYWRIGHT_CONFIG

# Create test directory and sample tests
mkdir -p tests

cat > tests/demo.spec.js << 'DEMO_TEST'
import { test, expect } from '@playwright/test';

test('Playwright VNC Demo', async ({ page }) => {
  console.log('🚀 Starting Playwright demo');
  console.log('👀 Watch the browser in VNC at http://localhost:6080');
  
  // Navigate to Playwright homepage
  await page.goto('https://playwright.dev/');
  
  // Take a screenshot
  await page.screenshot({ path: 'playwright-demo.png', fullPage: true });
  
  // Verify title
  await expect(page).toHaveTitle(/Playwright/);
  
  // Click on Get Started
  await page.getByRole('link', { name: 'Get started' }).click();
  
  // Wait to see the navigation
  await page.waitForTimeout(2000);
  
  // Verify we're on the docs page
  await expect(page.getByRole('heading', { name: 'Installation' })).toBeVisible();
  
  // Keep browser open for viewing
  await page.waitForTimeout(3000);
  
  console.log('✅ Demo complete! Browser should be visible in VNC desktop');
});

test('Todo MVC Interactive Demo', async ({ page }) => {
  console.log('🎯 Starting interactive TodoMVC demo');
  
  await page.goto('https://demo.playwright.dev/todomvc');
  
  // Add some todos with delays for visibility
  const input = page.getByPlaceholder('What needs to be done?');
  
  await input.fill('✅ Set up Playwright VNC environment');
  await page.waitForTimeout(1000);
  await input.press('Enter');
  
  await input.fill('🖥️ Watch tests in VNC desktop');
  await page.waitForTimeout(1000);
  await input.press('Enter');
  
  await input.fill('🎭 Create amazing automated tests');
  await page.waitForTimeout(1000);
  await input.press('Enter');
  
  // Mark first item as complete
  await page.getByTestId('todo-item').first().getByRole('checkbox').check();
  await page.waitForTimeout(1500);
  
  // Verify completion
  await expect(page.getByTestId('todo-item').first()).toHaveClass(/completed/);
  
  // Filter to show only active items
  await page.getByRole('link', { name: 'Active' }).click();
  await page.waitForTimeout(1500);
  
  // Take final screenshot
  await page.screenshot({ path: 'todomvc-demo.png' });
  
  // Keep browser open for final viewing
  await page.waitForTimeout(3000);
  
  console.log('✅ Interactive demo complete!');
});
DEMO_TEST

cat > tests/browser-features.spec.js << 'FEATURES_TEST'
import { test, expect } from '@playwright/test';

test('Browser Feature Showcase', async ({ page }) => {
  console.log('🌟 Showcasing browser automation features');
  
  // Test form interactions
  await page.goto('https://playwright.dev/');
  
  // Search functionality
  await page.getByRole('button', { name: 'Search' }).click();
  await page.getByPlaceholder('Search docs').fill('browser');
  await page.waitForTimeout(1000);
  await page.getByPlaceholder('Search docs').press('Escape');
  
  // Navigation
  await page.getByRole('link', { name: 'API' }).click();
  await page.waitForTimeout(2000);
  
  // Scroll to show page interaction
  await page.evaluate(() => window.scrollTo(0, 500));
  await page.waitForTimeout(1000);
  await page.evaluate(() => window.scrollTo(0, 0));
  
  // Take screenshot of final state
  await page.screenshot({ path: 'browser-features.png' });
  
  console.log('✅ Browser features demonstrated');
});

test('Mobile Simulation', async ({ browser }) => {
  console.log('📱 Testing mobile browser simulation');
  
  // Create mobile context
  const context = await browser.newContext({
    viewport: { width: 375, height: 667 },
    userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X) AppleWebKit/605.1.15'
  });
  
  const page = await context.newPage();
  
  await page.goto('https://playwright.dev/');
  
  // Mobile-specific interactions
  await page.getByRole('button', { name: 'Toggle navigation' }).click();
  await page.waitForTimeout(1000);
  
  await page.getByRole('link', { name: 'Get started' }).click();
  await page.waitForTimeout(2000);
  
  await page.screenshot({ path: 'mobile-simulation.png' });
  
  // Keep open for viewing
  await page.waitForTimeout(3000);
  
  await context.close();
  console.log('✅ Mobile simulation complete');
});
FEATURES_TEST

# Add npm scripts
npm pkg set scripts.test="playwright test"
npm pkg set scripts.test:headed="playwright test --headed"
npm pkg set scripts.test:ui="playwright test --ui"
npm pkg set scripts.test:debug="playwright test --debug"
npm pkg set scripts.demo="playwright test tests/demo.spec.js --headed"

# Create VS Code settings
mkdir -p .vscode
cat > .vscode/settings.json << 'VSCODE_SETTINGS'
{
  "playwright.reuseBrowser": true,
  "playwright.showTrace": true,
  "playwright.env": {
    "DISPLAY": ":1"
  },
  "terminal.integrated.env.linux": {
    "DISPLAY": ":1"
  },
  "files.exclude": {
    "**/node_modules": true,
    "**/playwright-report": true,
    "**/test-results": true
  }
}
VSCODE_SETTINGS

# Create README
cat > README.md << 'README'
# Playwright VNC Development Environment

## Overview
This environment provides a complete Playwright testing setup with visual browser automation accessible via web browser.

## Access URLs
- **VS Code (code-server)**: http://localhost:8080
- **VNC Desktop**: http://localhost:6080  
- **VNC Direct**: localhost:5901
- **Password**: vscode

## Quick Start
1. Open http://localhost:8080 in your browser (VS Code)
2. Open http://localhost:6080 in another tab (VNC Desktop)
3. In VS Code, navigate to this workspace
4. Run tests and watch browsers in the VNC desktop!

## Running Tests
```bash
# Run demo tests with visible browsers
npm run demo

# Run all tests with browsers visible
npm run test:headed

# Open Playwright UI (interactive test runner)
npm run test:ui

# Debug a specific test
npm run test:debug
```

## Test Files
- `tests/demo.spec.js` - Basic Playwright demonstration
- `tests/browser-features.spec.js` - Advanced browser features
- Add your own test files to the `tests/` directory

## Tips
- Tests run with `slowMo: 200` so you can see the automation
- Browsers appear in the VNC desktop window
- Screenshots and videos are saved in `test-results/`
- HTML reports are generated in `playwright-report/`

## Service Management
```bash
# Check service status
sudo systemctl status vnc-server novnc-server code-server

# Restart services
sudo systemctl restart vnc-server novnc-server code-server

# View logs
sudo journalctl -u vnc-server -f
```
README

log_success "Playwright workspace and demo tests created"

#==============================================================================
# STEP 10: Create systemd Services
#==============================================================================
log_info "Step 10: Creating systemd services..."

# VNC Service
cat > /etc/systemd/system/vnc-server.service << VNC_SERVICE
[Unit]
Description=VNC Server (Xvfb + x11vnc)
After=multi-user.target network.target
Wants=network.target

[Service]
Type=exec
User=root
Group=root
Environment="HOME=/root"
Environment="DISPLAY_NUM=$DISPLAY_NUM"
Environment="VNC_PORT=$VNC_PORT"
Environment="DISPLAY=:$DISPLAY_NUM"
ExecStart=/usr/local/bin/start-vnc-server
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
VNC_SERVICE

# noVNC Service
cat > /etc/systemd/system/novnc-server.service << NOVNC_SERVICE
[Unit]
Description=noVNC Web VNC Client
After=vnc-server.service
Wants=vnc-server.service

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/usr/local/novnc/noVNC-1.2.0
ExecStart=/usr/local/novnc/noVNC-1.2.0/utils/launch.sh --listen $NOVNC_PORT --vnc localhost:$VNC_PORT
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
NOVNC_SERVICE

# code-server Service
cat > /etc/systemd/system/code-server.service << CODESERVER_SERVICE
[Unit]
Description=VS Code Server
After=vnc-server.service
Wants=vnc-server.service

[Service]
Type=simple
User=root
Group=root
Environment="HOME=/root"
Environment="DISPLAY=:$DISPLAY_NUM"
WorkingDirectory=/root/workspace
ExecStart=/usr/bin/code-server --config /root/.config/code-server/config.yaml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
CODESERVER_SERVICE

# Reload systemd and enable services
systemctl daemon-reload
systemctl enable vnc-server novnc-server code-server

log_success "Systemd services created and enabled"

#==============================================================================
# STEP 11: Create Management Scripts
#==============================================================================
log_info "Step 11: Creating management scripts..."

# Main control script
cat > /usr/local/bin/playwright-vnc << 'CONTROL_SCRIPT'
#!/bin/bash

VNC_PORT=5901
NOVNC_PORT=6080
CODESERVER_PORT=8080
DISABLE_CODESERVER_AUTH="DISABLE_CODESERVER_AUTH_PLACEHOLDER"
DISABLE_VNC_AUTH="DISABLE_VNC_AUTH_PLACEHOLDER"

case "$1" in
    start)
        echo "Starting Playwright VNC environment..."
        systemctl start vnc-server novnc-server code-server
        sleep 5
        echo "Services started!"
        echo "Access at:"
        if [ "$DISABLE_CODESERVER_AUTH" = "true" ]; then
            echo "  VS Code: http://localhost:$CODESERVER_PORT (no password)"
        else
            echo "  VS Code: http://localhost:$CODESERVER_PORT (password: vscode)"
        fi
        if [ "$DISABLE_VNC_AUTH" = "true" ]; then
            echo "  VNC Desktop: http://localhost:$NOVNC_PORT (no password)"
        else
            echo "  VNC Desktop: http://localhost:$NOVNC_PORT (password: vscode)"
        fi
        ;;
    
    stop)
        echo "Stopping Playwright VNC environment..."
        systemctl stop vnc-server novnc-server code-server
        echo "Services stopped!"
        ;;
    
    restart)
        echo "Restarting Playwright VNC environment..."
        systemctl restart vnc-server novnc-server code-server
        sleep 5
        echo "Services restarted!"
        ;;
    
    status)
        echo "=== Service Status ==="
        systemctl status vnc-server novnc-server code-server --no-pager
        echo ""
        echo "=== Port Status ==="
        netstat -tulpn | grep -E ":($VNC_PORT|$NOVNC_PORT|$CODESERVER_PORT)" || echo "No services listening"
        ;;
    
    logs)
        service="${2:-vnc-server}"
        echo "Following logs for $service (Ctrl+C to exit)..."
        journalctl -u "$service" -f
        ;;
    
    test)
        echo "Running Playwright demo tests..."
        cd /root/workspace
        npm run demo
        ;;
    
    url)
        echo "Access URLs:"
        if [ "$DISABLE_CODESERVER_AUTH" = "true" ]; then
            echo "  VS Code (code-server): http://localhost:$CODESERVER_PORT (no password)"
        else
            echo "  VS Code (code-server): http://localhost:$CODESERVER_PORT (password: vscode)"
        fi
        if [ "$DISABLE_VNC_AUTH" = "true" ]; then
            echo "  VNC Desktop (noVNC): http://localhost:$NOVNC_PORT (no password)"
        else
            echo "  VNC Desktop (noVNC): http://localhost:$NOVNC_PORT (password: vscode)"
        fi
        echo "  VNC Direct: localhost:$VNC_PORT"
        ;;
    
    security)
        echo "Security Configuration:"
        echo "  code-server auth: $([ "$DISABLE_CODESERVER_AUTH" = "true" ] && echo "DISABLED" || echo "ENABLED")"
        echo "  VNC auth: $([ "$DISABLE_VNC_AUTH" = "true" ] && echo "DISABLED" || echo "ENABLED")"
        echo ""
        if [ "$DISABLE_CODESERVER_AUTH" = "true" ] || [ "$DISABLE_VNC_AUTH" = "true" ]; then
            echo "⚠️  WARNING: Some authentication is disabled!"
            echo "   Only use this configuration in trusted networks."
            echo "   For production use, enable authentication."
        else
            echo "✅ Authentication is enabled for all services."
        fi
        ;;
    
    *)
        echo "Playwright VNC Development Environment"
        echo ""
        echo "Usage: $0 {start|stop|restart|status|logs|test|url|security}"
        echo ""
        echo "Commands:"
        echo "  start    - Start all services"
        echo "  stop     - Stop all services"
        echo "  restart  - Restart all services"
        echo "  status   - Show service status and ports"
        echo "  logs     - Follow service logs (specify service name)"
        echo "  test     - Run demo Playwright tests"
        echo "  url      - Show access URLs and auth status"
        echo "  security - Show security configuration"
        echo ""
        echo "Examples:"
        echo "  $0 start"
        echo "  $0 logs vnc-server"
        echo "  $0 test"
        echo "  $0 security"
        ;;
esac
CONTROL_SCRIPT

# Replace placeholders with actual values
sed -i "s/DISABLE_CODESERVER_AUTH_PLACEHOLDER/$DISABLE_CODESERVER_AUTH/g" /usr/local/bin/playwright-vnc
sed -i "s/DISABLE_VNC_AUTH_PLACEHOLDER/$DISABLE_VNC_AUTH/g" /usr/local/bin/playwright-vnc

chmod +x /usr/local/bin/playwright-vnc

# Create update script
cat > /usr/local/bin/update-playwright << 'UPDATE_SCRIPT'
#!/bin/bash

echo "Updating Playwright browsers..."
cd /root/workspace

# Update Playwright
npm update @playwright/test

# Update browsers
npx playwright install

echo "Playwright updated!"
UPDATE_SCRIPT

chmod +x /usr/local/bin/update-playwright

log_success "Management scripts created"

#==============================================================================
# STEP 12: Add Helpful Aliases and Environment
#==============================================================================
log_info "Step 12: Setting up shell environment..."

# Add helpful aliases to root's bashrc
cat >> /root/.bashrc << 'BASHRC_ADDITIONS'

# Playwright VNC Development Environment
export DISPLAY=:1
export PLAYWRIGHT_BROWSERS_PATH=/ms-playwright

# Quick access aliases
alias pw='cd /root/workspace'
alias pw-test='cd /root/workspace && npm run test:headed'
alias pw-demo='cd /root/workspace && npm run demo'
alias pw-ui='cd /root/workspace && npm run test:ui'
alias vnc-status='playwright-vnc status'
alias vnc-start='playwright-vnc start'
alias vnc-restart='playwright-vnc restart'
alias vnc-url='playwright-vnc url'

# Environment info
echo ""
echo "🎭 Playwright VNC Development Environment Ready!"
echo "Type 'vnc-url' to see access URLs"
echo "Type 'pw-demo' to run demo tests"
echo "Type 'playwright-vnc help' for all commands"
BASHRC_ADDITIONS

log_success "Shell environment configured"

#==============================================================================
# STEP 13: Start Services and Final Verification
#==============================================================================
log_info "Step 13: Starting services and performing final verification..."

# Start all services
systemctl start vnc-server
sleep 8

systemctl start novnc-server
sleep 3

systemctl start code-server
sleep 3

# Check service status
VNC_STATUS=$(systemctl is-active vnc-server)
NOVNC_STATUS=$(systemctl is-active novnc-server)
CODESERVER_STATUS=$(systemctl is-active code-server)

echo ""
echo "=== SERVICE STATUS ==="
echo "VNC Server: $VNC_STATUS"
echo "noVNC Server: $NOVNC_STATUS"
echo "code-server: $CODESERVER_STATUS"

echo ""
echo "=== PORT STATUS ==="
netstat -tulpn | grep ":$VNC_PORT " >/dev/null && echo "✅ VNC listening on $VNC_PORT" || echo "❌ VNC not listening on $VNC_PORT"
netstat -tulpn | grep ":$NOVNC_PORT " >/dev/null && echo "✅ noVNC listening on $NOVNC_PORT" || echo "❌ noVNC not listening on $NOVNC_PORT"
netstat -tulpn | grep ":$CODESERVER_PORT " >/dev/null && echo "✅ code-server listening on $CODESERVER_PORT" || echo "❌ code-server not listening on $CODESERVER_PORT"

# Final status check
ALL_SERVICES_RUNNING=true
if [ "$VNC_STATUS" != "active" ]; then ALL_SERVICES_RUNNING=false; fi
if [ "$NOVNC_STATUS" != "active" ]; then ALL_SERVICES_RUNNING=false; fi
if [ "$CODESERVER_STATUS" != "active" ]; then ALL_SERVICES_RUNNING=false; fi

echo ""
if [ "$ALL_SERVICES_RUNNING" = true ]; then
    log_success "All services are running successfully!"
    
    echo ""
    echo "=================================================================="
    echo "🎉 PLAYWRIGHT VNC DEVELOPMENT ENVIRONMENT SETUP COMPLETE!"
    echo "=================================================================="
    echo ""
    echo "🌐 ACCESS YOUR ENVIRONMENT:"
    if [ "$DISABLE_CODESERVER_AUTH" = "true" ]; then
        echo "  VS Code (code-server): http://localhost:$CODESERVER_PORT (no password)"
    else
        echo "  VS Code (code-server): http://localhost:$CODESERVER_PORT (password: $VNC_PASSWORD)"
    fi
    if [ "$DISABLE_VNC_AUTH" = "true" ]; then
        echo "  VNC Desktop (noVNC):   http://localhost:$NOVNC_PORT (no password)"
    else
        echo "  VNC Desktop (noVNC):   http://localhost:$NOVNC_PORT (password: $VNC_PASSWORD)"
    fi
    echo "  VNC Direct Connection: localhost:$VNC_PORT"
    echo ""
    echo "🚀 QUICK START:"
    echo "  1. Open VS Code:       http://localhost:$CODESERVER_PORT"
    if [ "$DISABLE_CODESERVER_AUTH" = "false" ]; then
        echo "     Password:          $VNC_PASSWORD"
    fi
    echo "  2. Open VNC Desktop:   http://localhost:$NOVNC_PORT (in another tab)"
    if [ "$DISABLE_VNC_AUTH" = "false" ]; then
        echo "     Password:          $VNC_PASSWORD"
    fi
    echo "  3. In VS Code, the workspace is already open at /root/workspace"
    echo "  4. Run demo tests:     Open terminal and type 'npm run demo'"
    echo "  5. Watch browsers:     See automation in the VNC desktop tab!"
    echo ""
    echo "🔒 SECURITY:"
    echo "  code-server auth: $([ "$DISABLE_CODESERVER_AUTH" = "true" ] && echo "DISABLED" || echo "ENABLED")"
    echo "  VNC auth: $([ "$DISABLE_VNC_AUTH" = "true" ] && echo "DISABLED" || echo "ENABLED")"
    if [ "$DISABLE_CODESERVER_AUTH" = "true" ] || [ "$DISABLE_VNC_AUTH" = "true" ]; then
        echo "  ⚠️  WARNING: Some authentication is disabled!"
        echo "     Only use this in trusted networks."
    fi
    echo ""
    echo "📁 WORKSPACE STRUCTURE:"
    echo "  /root/workspace/               - Main development directory"
    echo "  /root/workspace/tests/         - Test files"
    echo "  /root/workspace/playwright.config.js - Playwright configuration"
    echo "  /root/workspace/package.json   - Node.js project file"
    echo ""
    echo "🧪 AVAILABLE TEST COMMANDS:"
    echo "  npm run demo          - Run demonstration tests"
    echo "  npm run test:headed   - Run all tests with visible browsers"
    echo "  npm run test:ui       - Open Playwright UI (interactive)"
    echo "  npm run test:debug    - Debug tests step by step"
    echo ""
    echo "🛠️  MANAGEMENT COMMANDS:"
    echo "  playwright-vnc status    - Check all services"
    echo "  playwright-vnc restart   - Restart all services"
    echo "  playwright-vnc test      - Run demo tests"
    echo "  playwright-vnc url       - Show access URLs"
    echo "  playwright-vnc security  - Show security configuration"
    echo "  update-playwright        - Update Playwright and browsers"
    echo ""
    echo "📝 HELPFUL ALIASES (available in terminal):"
    echo "  pw           - Go to workspace directory"
    echo "  pw-demo      - Run demo tests"
    echo "  pw-test      - Run tests with visible browsers"
    echo "  vnc-status   - Check service status"
    echo "  vnc-url      - Show access URLs"
    echo ""
    echo "🔧 TROUBLESHOOTING:"
    echo "  Service logs:     playwright-vnc logs [service-name]"
    echo "  Restart services: playwright-vnc restart"
    echo "  Service status:   playwright-vnc status"
    echo ""
    echo "💡 TIPS:"
    echo "  - Services auto-start on boot"
    echo "  - Tests run slowly (200ms delay) so you can see the automation"
    echo "  - Screenshots and videos saved in test-results/"
    echo "  - HTML reports generated in playwright-report/"
    echo "  - Use the VNC desktop tab to watch browser automation"
    echo ""
    echo "=================================================================="
    
else
    log_error "Some services failed to start properly"
    echo ""
    echo "❌ SERVICE ISSUES DETECTED:"
    if [ "$VNC_STATUS" != "active" ]; then
        echo "  VNC Server: $VNC_STATUS"
        echo "    Check: journalctl -u vnc-server -n 20"
    fi
    if [ "$NOVNC_STATUS" != "active" ]; then
        echo "  noVNC Server: $NOVNC_STATUS"
        echo "    Check: journalctl -u novnc-server -n 20"
    fi
    if [ "$CODESERVER_STATUS" != "active" ]; then
        echo "  code-server: $CODESERVER_STATUS"
        echo "    Check: journalctl -u code-server -n 20"
    fi
    echo ""
    echo "🔧 TROUBLESHOOTING STEPS:"
    echo "  1. Check logs: playwright-vnc logs vnc-server"
    echo "  2. Restart services: playwright-vnc restart"
    echo "  3. Check status: playwright-vnc status"
    echo "  4. Manual start: /usr/local/bin/start-vnc-server"
fi

#==============================================================================
# STEP 14: Create Backup and Restore Scripts
#==============================================================================
log_info "Step 14: Creating backup and restore utilities..."

# Backup script
cat > /usr/local/bin/backup-playwright-env << 'BACKUP_SCRIPT'
#!/bin/bash

BACKUP_DIR="/root/playwright-backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/playwright_backup_$TIMESTAMP.tar.gz"

echo "Creating backup of Playwright VNC environment..."

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Create backup
tar -czf "$BACKUP_FILE" \
    /root/workspace \
    /root/.config/code-server \
    /root/.vnc \
    /etc/systemd/system/vnc-server.service \
    /etc/systemd/system/novnc-server.service \
    /etc/systemd/system/code-server.service \
    /usr/local/bin/start-vnc-server \
    /usr/local/bin/playwright-vnc \
    /usr/local/bin/update-playwright \
    2>/dev/null

if [ $? -eq 0 ]; then
    echo "✅ Backup created: $BACKUP_FILE"
    echo "Backup size: $(du -h $BACKUP_FILE | cut -f1)"
    
    # Keep only last 5 backups
    cd "$BACKUP_DIR"
    ls -t playwright_backup_*.tar.gz | tail -n +6 | xargs -r rm
    echo "Old backups cleaned up (keeping 5 most recent)"
else
    echo "❌ Backup failed"
    exit 1
fi
BACKUP_SCRIPT

chmod +x /usr/local/bin/backup-playwright-env

# Restore script
cat > /usr/local/bin/restore-playwright-env << 'RESTORE_SCRIPT'
#!/bin/bash

BACKUP_DIR="/root/playwright-backups"

if [ -z "$1" ]; then
    echo "Available backups:"
    ls -la "$BACKUP_DIR"/playwright_backup_*.tar.gz 2>/dev/null || echo "No backups found"
    echo ""
    echo "Usage: $0 <backup_file>"
    echo "Example: $0 $BACKUP_DIR/playwright_backup_20240730_140000.tar.gz"
    exit 1
fi

BACKUP_FILE="$1"

if [ ! -f "$BACKUP_FILE" ]; then
    echo "❌ Backup file not found: $BACKUP_FILE"
    exit 1
fi

echo "Restoring from backup: $BACKUP_FILE"
echo "⚠️  This will overwrite current configuration!"
read -p "Continue? (y/N): " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Restore cancelled"
    exit 0
fi

# Stop services
echo "Stopping services..."
systemctl stop vnc-server novnc-server code-server

# Restore files
echo "Restoring files..."
tar -xzf "$BACKUP_FILE" -C /

# Reload systemd
systemctl daemon-reload

# Restart services
echo "Starting services..."
systemctl start vnc-server novnc-server code-server

echo "✅ Restore completed!"
echo "Check status with: playwright-vnc status"
RESTORE_SCRIPT

chmod +x /usr/local/bin/restore-playwright-env

log_success "Backup and restore utilities created"

#==============================================================================
# STEP 15: Create Health Check Script
#==============================================================================
log_info "Step 15: Creating health check and monitoring..."

cat > /usr/local/bin/health-check-vnc << 'HEALTH_CHECK'
#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "🏥 Playwright VNC Environment Health Check"
echo "=========================================="

# Check services
echo ""
echo "📋 SERVICE STATUS:"
services=("vnc-server" "novnc-server" "code-server")
all_healthy=true

for service in "${services[@]}"; do
    status=$(systemctl is-active "$service")
    if [ "$status" = "active" ]; then
        echo -e "  ✅ $service: ${GREEN}$status${NC}"
    else
        echo -e "  ❌ $service: ${RED}$status${NC}"
        all_healthy=false
    fi
done

# Check ports
echo ""
echo "🔌 PORT STATUS:"
ports=("5901:VNC" "6080:noVNC" "8080:code-server")

for port_info in "${ports[@]}"; do
    port=$(echo $port_info | cut -d: -f1)
    name=$(echo $port_info | cut -d: -f2)
    
    if netstat -tulpn | grep ":$port " >/dev/null; then
        echo -e "  ✅ $name (port $port): ${GREEN}listening${NC}"
    else
        echo -e "  ❌ $name (port $port): ${RED}not listening${NC}"
        all_healthy=false
    fi
done

# Check X11 display
echo ""
echo "🖥️  DISPLAY STATUS:"
if DISPLAY=:1 xdpyinfo >/dev/null 2>&1; then
    echo -e "  ✅ X11 Display :1: ${GREEN}accessible${NC}"
else
    echo -e "  ❌ X11 Display :1: ${RED}not accessible${NC}"
    all_healthy=false
fi

# Check VNC processes
echo ""
echo "🔄 PROCESS STATUS:"
processes=("Xvfb.*:1:Virtual Display" "x11vnc.*:1:VNC Server" "xterm.*VNC Desktop:Window Manager")

for process_info in "${processes[@]}"; do
    process=$(echo $process_info | cut -d: -f1)
    name=$(echo $process_info | cut -d: -f3)
    
    if pgrep -f "$process" >/dev/null; then
        echo -e "  ✅ $name: ${GREEN}running${NC}"
    else
        echo -e "  ❌ $name: ${RED}not running${NC}"
        all_healthy=false
    fi
done

# Check disk space
echo ""
echo "💾 DISK SPACE:"
workspace_usage=$(df /root/workspace | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$workspace_usage" -lt 90 ]; then
    echo -e "  ✅ Workspace disk usage: ${GREEN}${workspace_usage}%${NC}"
else
    echo -e "  ⚠️  Workspace disk usage: ${YELLOW}${workspace_usage}%${NC}"
fi

# Check Playwright
echo ""
echo "🎭 PLAYWRIGHT STATUS:"
cd /root/workspace
if [ -d "node_modules/@playwright" ]; then
    pw_version=$(npx playwright --version 2>/dev/null | head -n1)
    echo -e "  ✅ Playwright: ${GREEN}installed ($pw_version)${NC}"
    
    # Check browsers
    browser_path="/ms-playwright"
    if [ -d "$browser_path" ]; then
        browser_count=$(find "$browser_path" -name "chrome" -o -name "firefox" -o -name "webkit" | wc -l)
        echo -e "  ✅ Browsers: ${GREEN}$browser_count installed${NC}"
    else
        echo -e "  ⚠️  Browsers: ${YELLOW}path not found${NC}"
    fi
else
    echo -e "  ❌ Playwright: ${RED}not installed${NC}"
    all_healthy=false
fi

# Overall status
echo ""
echo "=========================================="
if [ "$all_healthy" = true ]; then
    echo -e "🎉 Overall Status: ${GREEN}HEALTHY${NC}"
    echo "Environment is ready for Playwright testing!"
else
    echo -e "⚠️  Overall Status: ${YELLOW}ISSUES DETECTED${NC}"
    echo "Run 'playwright-vnc restart' to attempt fixes"
fi

echo ""
echo "💡 Quick Actions:"
echo "  playwright-vnc restart  - Restart all services"
echo "  playwright-vnc status   - Detailed service status"
echo "  playwright-vnc test     - Run demo tests"
HEALTH_CHECK

chmod +x /usr/local/bin/health-check-vnc

# Create cron job for health monitoring
cat > /etc/cron.d/playwright-vnc-health << 'CRON_HEALTH'
# Check Playwright VNC environment health every 5 minutes
*/5 * * * * root /usr/local/bin/health-check-vnc >/dev/null 2>&1 || /usr/local/bin/playwright-vnc restart
CRON_HEALTH

log_success "Health check and monitoring configured"

#==============================================================================
# STEP 16: Final System Optimization
#==============================================================================
log_info "Step 16: Applying final system optimizations..."

# Optimize for VNC performance
cat >> /etc/sysctl.conf << 'SYSCTL_OPTS'

# Playwright VNC Optimizations
# Increase shared memory for browser processes
kernel.shmmax = 268435456
kernel.shmall = 268435456

# Network optimizations for VNC
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
SYSCTL_OPTS

# Apply sysctl changes
sysctl -p >/dev/null 2>&1

# Create logrotate config for VNC logs
cat > /etc/logrotate.d/playwright-vnc << 'LOGROTATE'
/tmp/xvfb.log /tmp/x11vnc.log /tmp/xterm.log {
    daily
    missingok
    rotate 7
    compress
    notifempty
    create 644 root root
}
LOGROTATE

log_success "System optimizations applied"

#==============================================================================
# FINAL SUMMARY AND CLEANUP
#==============================================================================

# Create installation summary
cat > /root/INSTALLATION_SUMMARY.txt << SUMMARY
PLAYWRIGHT VNC DEVELOPMENT ENVIRONMENT
Installation completed: $(date)

CONFIGURATION:
- VNC Port: $VNC_PORT
- noVNC Port: $NOVNC_PORT  
- code-server Port: $CODESERVER_PORT
- Password: $VNC_PASSWORD
- Display: :$DISPLAY_NUM
- Resolution: 1920x1080x24
- code-server Auth: $([ "$DISABLE_CODESERVER_AUTH" = "true" ] && echo "DISABLED" || echo "ENABLED")
- VNC Auth: $([ "$DISABLE_VNC_AUTH" = "true" ] && echo "DISABLED" || echo "ENABLED")
- Node.js Version: $(node --version)
- Playwright Version: $(cd /root/workspace && npx playwright --version | head -n1)

ACCESS URLS:
- VS Code: http://localhost:$CODESERVER_PORT $([ "$DISABLE_CODESERVER_AUTH" = "true" ] && echo "(no password)" || echo "(password: $VNC_PASSWORD)")
- VNC Desktop: http://localhost:$NOVNC_PORT $([ "$DISABLE_VNC_AUTH" = "true" ] && echo "(no password)" || echo "(password: $VNC_PASSWORD)")
- VNC Direct: localhost:$VNC_PORT

SERVICES:
- vnc-server (Xvfb + x11vnc)
- novnc-server (Web VNC client)
- code-server (VS Code in browser)

MANAGEMENT COMMANDS:
- playwright-vnc {start|stop|restart|status|test|url|security}
- health-check-vnc
- backup-playwright-env
- restore-playwright-env <backup_file>
- update-playwright

FILES AND DIRECTORIES:
- Workspace: /root/workspace
- Config: /root/.config/code-server
- VNC: /root/.vnc
- Scripts: /usr/local/bin/
- Services: /etc/systemd/system/
- Logs: /tmp/ and journalctl

ALIASES:
- pw (go to workspace)
- pw-demo (run demo tests)
- vnc-status (check services)
- vnc-url (show URLs)
SUMMARY

# Cleanup installation files
cd /root
rm -f /tmp/novnc.zip /tmp/websockify.zip

log_success "Installation summary created: /root/INSTALLATION_SUMMARY.txt"

echo ""
echo "🧹 Installation cleanup completed"
echo ""

# Show final reminder
echo "=================================================================="
echo "✨ INSTALLATION COMPLETE!"
echo ""
echo "Your Playwright VNC development environment is ready!"
echo ""
echo "🎯 NEXT STEPS:"
echo "1. Open VS Code: http://localhost:$CODESERVER_PORT"
if [ "$DISABLE_CODESERVER_AUTH" = "false" ]; then
    echo "   Password: $VNC_PASSWORD"
fi
echo "2. Open VNC Desktop: http://localhost:$NOVNC_PORT"
if [ "$DISABLE_VNC_AUTH" = "false" ]; then
    echo "   Password: $VNC_PASSWORD"
fi
echo "3. Run demo: pw-demo (or npm run demo in terminal)"
echo "4. Security check: playwright-vnc security"
echo ""
echo "📖 Documentation: /root/INSTALLATION_SUMMARY.txt"
echo "🏥 Health Check: health-check-vnc"
echo "=================================================================="
