<#
.SYNOPSIS
    Скрипт для отправки текстового уведомления о запуске/перезагрузке компьютера/сервера.
.DESCRIPTION
    Отправляет простое текстовое уведомление через SMTP Яндекс.Почты при старте системы
.NOTES
    Author: System Administrator
    Date:   $(Get-Date -Format 'yyyy-MM-dd')
#>

# ==================== НАСТРОЙКИ (ИЗМЕНИТЕ ПОД СЕБЯ) ====================
$Config = @{
    # Настройки SMTP
    SmtpServer   = "smtp.yandex.ru"      # SMTP сервер
    SmtpPort     = 587                    # Порт (587 для TLS/STARTTLS)
    UseSSL       = $true                   # Использовать SSL/TLS
    
    # Учетные данные отправителя
    EmailFrom    = "mailname@yandex.ru"    # Адрес отправителя
    EmailUser    = "mailname@yandex.ru"    # Логин (обычно совпадает с email)
    EmailPassword = "mailpassw0rd"            # Пароль приложения/почты
    
    # Получатель (можно несколько через запятую)
    EmailTo      = "sendtomail@mail.ru"
    
    # Настройки темы письма
    # {0} - hostname, {1} - дата и время
    EmailSubject = "⚠️ Перезагрузка сервера {0} в {1}"
    
    # Текст письма 
    EmailBody = @"
Сервер {0} был перезагружен или аварийно выключен и автоматически включён.

Время запуска: {1}
Время работы с последней загрузки: {2}
Операционная система: {3}
Внешний IP-адрес: {4}

ВНИМАНИЕ: если это требуется, предпримите какие-либо действия!
"@
}
# ==================== КОНЕЦ НАСТРОЕК ====================

# Функция для получения внешнего IP-адреса
function Get-ExternalIP {
    try {
        Write-Host "  - Определение внешнего IP-адреса..." -ForegroundColor Gray
        
        # Пробуем разные сервисы для определения внешнего IP (на случай, если какой-то недоступен)
        $services = @(
            "ifconfig.me",
            "api.ipify.org",
            "icanhazip.com",
            "ipinfo.io/ip"
        )
        
        $externalIP = $null
        foreach ($service in $services) {
            try {
                $externalIP = (Invoke-WebRequest -Uri "http://$service" -UseBasicParsing -TimeoutSec 5).Content.Trim()
                if ($externalIP -match '^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$') {
                    Write-Host "    ✓ IP получен через $service : $externalIP" -ForegroundColor Green
                    break
                }
            } catch {
                Write-Host "    ✗ Не удалось получить IP через $service" -ForegroundColor DarkGray
                continue
            }
        }
        
        if ($externalIP) {
            return $externalIP
        } else {
            return "Не удалось определить внешний IP"
        }
    }
    catch {
        Write-Host "    ✗ Ошибка при определении внешнего IP: $($_.Exception.Message)" -ForegroundColor DarkGray
        return "Не удалось определить внешний IP"
    }
}

# Функция для получения информации о системе
function Get-SystemInfo {
    try {
        $hostname = $env:COMPUTERNAME
        $currentTime = Get-Date -Format "dd.MM.yyyy HH:mm:ss"
        
        # Пытаемся получить время загрузки
        try {
            $bootTimeObj = (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime
            $bootTime = $bootTimeObj.ToString('dd.MM.yyyy HH:mm:ss')
            $uptimeObj = (Get-Date) - $bootTimeObj
            $uptime = "$($uptimeObj.Days) дн. $($uptimeObj.Hours) ч. $($uptimeObj.Minutes) мин."
        } catch {
            $bootTime = $currentTime
            $uptime = "Не удалось определить"
        }
        
        # Получаем ОС
        try {
            $osInfo = (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).Caption
        } catch {
            $osInfo = "Не удалось определить"
        }
        
        # Получаем внешний IP
        $externalIP = Get-ExternalIP
        
        return @{
            Hostname    = $hostname
            CurrentTime = $currentTime
            BootTime    = $bootTime
            Uptime      = $uptime
            OS          = $osInfo
            ExternalIP  = $externalIP
        }
    }
    catch {
        Write-Warning "Не удалось получить полную информацию о системе: $($_.Exception.Message)"
        return @{
            Hostname    = $env:COMPUTERNAME
            CurrentTime = (Get-Date -Format "dd.MM.yyyy HH:mm:ss")
            BootTime    = (Get-Date -Format "dd.MM.yyyy HH:mm:ss")
            Uptime      = "Не удалось определить"
            OS          = "Не удалось определить"
            ExternalIP  = "Не удалось определить"
        }
    }
}

# Функция отправки email
function Send-StartupNotification {
    param(
        [hashtable]$Config,
        [hashtable]$SystemInfo
    )
    
    try {
        Write-Host "`nПодготовка уведомления о запуске сервера $($SystemInfo.Hostname)..." -ForegroundColor Cyan
        
        # Формируем тему письма с подстановкой hostname и времени
        $emailSubject = $Config.EmailSubject -f $SystemInfo.Hostname, $SystemInfo.CurrentTime
        
        # Формируем тело письма с подстановкой всех данных
        $emailBody = $Config.EmailBody -f @(
            $SystemInfo.Hostname,
            $SystemInfo.BootTime,
            $SystemInfo.Uptime,
            $SystemInfo.OS,
            $SystemInfo.ExternalIP
        )
        
        # Выводим содержимое письма для контроля
        Write-Host "`n📧 Содержимое письма:" -ForegroundColor Yellow
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
        Write-Host "ТЕМА: $emailSubject" -ForegroundColor White
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
        Write-Host $emailBody -ForegroundColor White
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
        
        # Создаем сообщение
        $mailMessage = New-Object System.Net.Mail.MailMessage
        
        # Отправитель
        $mailMessage.From = New-Object System.Net.Mail.MailAddress($Config.EmailFrom)
        
        # Получатели (поддерживаем как строку, так и массив)
        if ($Config.EmailTo -is [array]) {
            foreach ($recipient in $Config.EmailTo) {
                $mailMessage.To.Add($recipient.Trim())
            }
        } else {
            $Config.EmailTo -split ',' | ForEach-Object {
                $mailMessage.To.Add($_.Trim())
            }
        }
        
        $mailMessage.Subject = $emailSubject
        $mailMessage.Body = $emailBody
        $mailMessage.IsBodyHtml = $false  # Отключаем HTML!
        $mailMessage.Priority = [System.Net.Mail.MailPriority]::High
        
        # Настройки SMTP
        $smtpClient = New-Object System.Net.Mail.SmtpClient($Config.SmtpServer, $Config.SmtpPort)
        $smtpClient.EnableSsl = $Config.UseSSL
        $smtpClient.Credentials = New-Object System.Net.NetworkCredential($Config.EmailUser, $Config.EmailPassword)
        $smtpClient.Timeout = 30000 # 30 секунд таймаут
        
        # Отправляем
        Write-Host "`nОтправка уведомления на $($Config.EmailTo)..." -ForegroundColor Yellow
        $smtpClient.Send($mailMessage)
        
        Write-Host "✓ Уведомление успешно отправлено!" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "✗ Ошибка при отправке уведомления: $($_.Exception.Message)"
        
        if ($_.Exception.InnerException) {
            Write-Warning "Детали: $($_.Exception.InnerException.Message)"
        }
        
        return $false
    }
    finally {
        if ($mailMessage) { $mailMessage.Dispose() }
        if ($smtpClient) { $smtpClient.Dispose() }
    }
}

# Основная логика
function Main {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  МОНИТОРИНГ ЗАПУСКА СИСТЕМЫ" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Начало выполнения: $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')" -ForegroundColor Gray
    
    # Получаем информацию о системе
    $systemInfo = Get-SystemInfo
    
    # Выводим информацию о системе
    Write-Host "`n📊 Информация о системе:" -ForegroundColor Yellow
    Write-Host "  - Имя хоста: $($systemInfo.Hostname)"
    Write-Host "  - Текущее время: $($systemInfo.CurrentTime)"
    Write-Host "  - Время запуска: $($systemInfo.BootTime)"
    Write-Host "  - Время работы: $($systemInfo.Uptime)"
    Write-Host "  - ОС: $($systemInfo.OS)"
    Write-Host "  - Внешний IP: $($systemInfo.ExternalIP)"
    
    # Отправляем уведомление
    $result = Send-StartupNotification -Config $Config -SystemInfo $systemInfo
    
    if ($result) {
        Write-Host "`n✅ Скрипт выполнен успешно" -ForegroundColor Green
    } else {
        Write-Host "`n❌ Скрипт завершился с ошибками" -ForegroundColor Red
        Write-Host "`n💡 Проверьте:" -ForegroundColor Yellow
        Write-Host "  - Логин и пароль (для Яндекса нужен пароль приложения)"
        Write-Host "  - Доступность smtp.yandex.ru:587"
        Write-Host "  - Настройки почтового ящика (IMAP должен быть включён)"
        Write-Host "  - Доступ в интернет для определения внешнего IP"
    }
    
    Write-Host "`n========================================" -ForegroundColor Cyan
    
    exit $(if ($result) { 0 } else { 1 })
}

# Запускаем
Main
