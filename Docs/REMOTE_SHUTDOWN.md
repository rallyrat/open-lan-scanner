# Remote shutdown — feasibility note

Advanced IP Scanner can attempt Windows remote shutdown/reboot with optional messaging. That path relies on Windows SMB/RPC administrative protocols and credentials.

## Open LAN Scanner stance

**Not implemented.** Presenting a non-functional Shut Down control would be dishonest.

### Why macOS has no drop-in equivalent

- There is no safe, generic “shut down this LAN host” API that works across Windows, macOS, Linux, and appliances without prior out-of-band setup.
- Windows-style remote shutdown typically needs administrative SMB/RPC access and stored or prompted credentials. Storing passwords in plain text is unacceptable; a secure credential UX is out of scope for v1.
- Apple Remote Desktop and MDM are separate products/protocols, not implied by a LAN scanner.

### Supported power-adjacent action

- **Wake-on-LAN** is implemented when a MAC address is known (including manually saved favorites).

### If you need remote power-off

Use the platform-native tool with explicit authentication, for example SSH (`shutdown`/`systemctl poweroff` on Unix) or your organization’s MDM / Apple Remote Desktop / Windows admin tooling. Open LAN Scanner can open SSH to a discovered host so you can run those commands yourself.
