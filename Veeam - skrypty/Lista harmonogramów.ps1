Get-VBRJob |
    Select-Object Name, JobType, IsScheduleEnabled, IsRunning |
    Sort-Object Name |
    Format-Table -AutoSize
