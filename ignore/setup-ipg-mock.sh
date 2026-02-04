#!/bin/bash

echo "=== Multi-Host File Deploy Script ==="

# Define hostnames array
# - please comment out the envs you want to connect to

HOSTNAMES=(
#    "dev7-cos01.dev.pdx10.clover.network"
#    "dev7-cos02.dev.pdx10.clover.network"
#    "dev7-cosbatch01.dev.pdx10.clover.network"
#    "dev7-auth01.dev.pdx10.clover.network"
    "stg2-cos01.dev.pdx10.clover.network"
    "stg2-cos02.dev.pdx10.clover.network"
    "stg2-cosbatch01.dev.pdx10.clover.network"
    "stg2-auth01.dev.pdx10.clover.network"
    # "sandboxprod-cosdevice01.dev.pdx10.clover.network"
    # "sandboxprod-cosdevice02.dev.pdx10.clover.network"
)

# Get user input
read -p "Enter username: " USERNAME
echo -n "Enter password: "
read -s PASSWORD
echo

# Validate inputs
if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
    echo "Error: Username and password are required"
    exit 1
fi

echo ""
echo "Will upload to these ${#HOSTNAMES[@]} hosts:"
for hostname in "${HOSTNAMES[@]}"; do
    echo "- $hostname"
done

echo ""
echo "Files to upload:"
echo "- ipg-mock-cxf-war-1.0-SNAPSHOT-war-exec.jar"
echo "- start.sh"
echo ""
echo "Commands to run after upload:"
echo "- chmod +x start.sh"
echo "- chmod +x ipg-mock-cxf-war-1.0-SNAPSHOT-war-exec.jar"
echo "- kill -15 \`cat ipg-mock.pid\`"
echo "- ./start.sh -c"

read -p "Continue? (y/N): " CONFIRM
if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

# Export variables for expect to use
export USERNAME
export PASSWORD

# Function to deploy to a single host
deploy_to_host() {
    local hostname=$1
    echo ""
    echo "Deploying to $hostname..."
    
    export HOSTNAME=$hostname
    
    expect << 'EOF'
set timeout 30

# Get variables from environment
set username $env(USERNAME)
set hostname $env(HOSTNAME) 
set password $env(PASSWORD)

# Upload ipg-mock-cxf-war-1.0-SNAPSHOT-war-exec.jar
puts "  Uploading ipg-mock-cxf-war-1.0-SNAPSHOT-war-exec.jar..."
spawn scp ipg-mock-cxf-war-1.0-SNAPSHOT-war-exec.jar $username@$hostname:~

expect {
    "Are you sure you want to continue connecting" {
        send "yes\r"
        expect "*password*"
        send "$password\r"
    }
    "*password*" {
        send "$password\r"
    }
    timeout {
        puts "  ERROR: ipg-mock-cxf-war-1.0-SNAPSHOT-war-exec.jar upload timed out"
        exit 1
    }
}

expect {
    eof {
        puts "  ✓ ipg-mock-cxf-war-1.0-SNAPSHOT-war-exec.jar uploaded"
    }
    timeout {
        puts "  ERROR: ipg-mock-cxf-war-1.0-SNAPSHOT-war-exec.jar upload failed"
        exit 1
    }
}

# Upload start.sh
puts "  Uploading start.sh..."
spawn scp start.sh $username@$hostname:~

expect {
    "Are you sure you want to continue connecting" {
        send "yes\r"
        expect "*password*"
        send "$password\r"
    }
    "*password*" {
        send "$password\r"
    }
    timeout {
        puts "  ERROR: start.sh upload timed out"
        exit 1
    }
}

expect {
    eof {
        puts "  ✓ start.sh uploaded"
    }
    timeout {
        puts "  ERROR: start.sh upload failed"
        exit 1
    }
}

puts "  ✓ All files uploaded to $hostname"
EOF

    if [ $? -eq 0 ]; then
        echo "  ✓ Successfully uploaded files to $hostname"
    else
        echo "  ✗ Failed to upload files to $hostname"
        return 1
    fi
}

# Function to execute commands on a single host
execute_on_host() {
    local hostname=$1
    echo ""
    echo "Executing commands on $hostname..."
    
    export HOSTNAME=$hostname
    
    expect << 'EOF'
set timeout 60

# Get variables from environment
set username $env(USERNAME)
set hostname $env(HOSTNAME) 
set password $env(PASSWORD)

puts "  Connecting via SSH..."
spawn ssh $username@$hostname

expect {
    "Are you sure you want to continue connecting" {
        send "yes\r"
        expect "*password*"
        send "$password\r"
    }
    "*password*" {
        send "$password\r"
    }
    timeout {
        puts "  ERROR: SSH connection timed out"
        exit 1
    }
}

# Wait for shell prompt
expect {
    "*$*" { }
    "*#*" { }
    "*>*" { }
    timeout {
        puts "  ERROR: Failed to get shell prompt"
        exit 1
    }
}

puts "  Setting executable permissions..."

# Make start.sh executable
send "chmod +x start.sh\r"
expect {
    "*$*" { }
    "*#*" { }
    "*>*" { }
    timeout {
        puts "  ERROR: chmod start.sh command timed out"
        exit 1
    }
}

# Make jar executable
send "chmod +x ipg-mock-cxf-war-1.0-SNAPSHOT-war-exec.jar\r"
expect {
    "*$*" { }
    "*#*" { }
    "*>*" { }
    timeout {
        puts "  ERROR: chmod jar command timed out"
        exit 1
    }
}

puts "  Stopping existing process..."

# Kill existing process if pid file exists
send "kill -15 \$(cat ipg-mock.pid)\r"
expect {
    "*killed*" {
        puts "  Process killed successfully"
    }
    "*No such file*" {
        puts "  No pid file found"
    }
    "*No such process*" {
        puts "  Process not running"
    }
    "*$*" { }
    "*#*" { }
    "*>*" { }
    timeout {
        puts "  ERROR: kill command timed out"
        exit 1
    }
}

# Wait a moment for the process to stop gracefully
sleep 2

puts "  Starting application..."

# Start the application
send "./start.sh -c\r"

# Give it a moment to start
sleep 3

# Check if it's running (optional - you might want to customize this)
expect {
    "*$*" { 
        puts "  ✓ start.sh command executed"
    }
    "*#*" { 
        puts "  ✓ start.sh command executed"
    }
    "*>*" { 
        puts "  ✓ start.sh command executed"
    }
    timeout {
        puts "  ✓ start.sh command sent (may still be running in background)"
    }
}

# Exit SSH session
send "exit\r"
expect eof

puts "  ✓ Commands executed on $hostname"
EOF

    if [ $? -eq 0 ]; then
        echo "  ✓ Successfully executed commands on $hostname"
    else
        echo "  ✗ Failed to execute commands on $hostname"
        return 1
    fi
}

# Deploy to all hosts (upload files first)
echo ""
echo "=== Phase 1: Uploading files ==="
UPLOAD_SUCCESS=true

for hostname in "${HOSTNAMES[@]}"; do
    deploy_to_host "$hostname" || UPLOAD_SUCCESS=false
done

if [ "$UPLOAD_SUCCESS" = false ]; then
    echo ""
    echo "⚠️  Some file uploads failed. Do you want to continue with command execution?"
    read -p "Continue? (y/N): " CONTINUE_CONFIRM
    if [[ ! $CONTINUE_CONFIRM =~ ^[Yy]$ ]]; then
        echo "Stopped after upload phase."
        exit 1
    fi
fi

# Execute commands on all hosts
echo ""
echo "=== Phase 2: Executing commands ==="

for hostname in "${HOSTNAMES[@]}"; do
    execute_on_host "$hostname"
done

# Clear password variable and unset array
unset USERNAME
unset PASSWORD
unset HOSTNAMES

echo ""
echo "=== Deployment completed! ==="
