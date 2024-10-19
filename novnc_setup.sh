import os
import subprocess

# Set username and password
username = "user" #@param {type:"string"}
password = "root" #@param {type:"string"}

print("Creating User and Setting it up")

# Create user and set permissions
os.system(f"useradd -m {username}")
os.system(f"adduser {username} sudo")
os.system(f"echo '{username}:{password}' | sudo chpasswd")
os.system("sed -i 's/\/bin\/sh/\/bin\/bash/g' /etc/passwd")
print(f"User created and configured with username `{username}` and password `{password}`")

# Grant full permissions to the user's home directory
directory_path = f"/home/{username}"
os.system(f"chmod -R 777 {directory_path}")

# Set the user as sudo without a password requirement
sudoers_entry = f"{username} ALL=(ALL:ALL) NOPASSWD:ALL"
with open("/etc/sudoers", "a") as file:
    file.write(sudoers_entry + "\n")

print("User granted full administrative permissions.")

# Install necessary components for noVNC and XFCE4
print("Installing XFCE4 desktop environment, VNC server, and noVNC...")
os.system("apt update && apt install -y xfce4 xfce4-goodies x11vnc xvfb websockify")

# Configure the virtual display and VNC server
os.system("Xvfb :1 -screen 0 1024x768x16 &")
os.system("x11vnc -display :1 -rfbport 5900 -xkb -forever -bg")
os.system("git clone https://github.com/novnc/noVNC.git")

# Start noVNC server
os.chdir("noVNC")
os.system("websockify --web ./ --wrap-mode=ignore 5901 localhost:5900 &")

print("noVNC and VNC server have been set up. You can now access your desktop using noVNC.")

# Install VS Code
vs_url = "https://az764295.vo.msecnd.net/stable/695af097c7bd098fbf017ce3ac85e09bbc5dda06/code_1.79.2-1686734195_amd64.deb"
file_name = os.path.basename(vs_url)
install_path = "/content/"

print("Installing VS Code...")
subprocess.run(["wget", vs_url, "-O", os.path.join(install_path, file_name)])
subprocess.run(['sudo', 'dpkg', '-i', os.path.join(install_path, file_name)])
os.system("apt install --assume-yes --fix-broken")

print("VS Code installed successfully!")

# Set up ngrok to expose port 5901 for noVNC
print("Setting up ngrok for remote access...")
os.system("pip install pyngrok")
from pyngrok import ngrok

# Expose noVNC on port 5901
public_url = ngrok.connect(5901)
print(f"Access your noVNC interface at: {public_url}")
