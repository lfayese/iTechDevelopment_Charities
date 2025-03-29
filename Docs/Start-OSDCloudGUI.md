---
external help file: OSD-help.xml
Module Name: OSD
online version: https://github.com/OSDeploy/OSD/tree/master/Docs
schema: 2.0.0
---

# Start-OSDCloudGUI

## SYNOPSIS
OSDCloud imaging using the command line

## SYNTAX

```
Start-OSDCloudGUI [[-BrandName] <String>] [[-BrandColor] <String>] [[-ComputerManufacturer] <String>]
 [[-ComputerProduct] <String>] [-v2] [<CommonParameters>]
```

## DESCRIPTION
OSDCloud imaging using the command line

## EXAMPLES

### EXAMPLE 1
```
Start-OSDCloudGUI
```

## PARAMETERS

### -BrandName
The custom Brand for OSDCloudGUI

```yaml
Type: String
Parameter Sets: (All)
Aliases: Brand

Required: False
Position: 1
Default value: $Global:OSDModuleResource.StartOSDCloudGUI.BrandName
Accept pipeline input: False
Accept wildcard characters: False
```

### -BrandColor
Color for the OSDCloudGUI Brand

```yaml
Type: String
Parameter Sets: (All)
Aliases: Color

Required: False
Position: 2
Default value: $Global:OSDModuleResource.StartOSDCloudGUI.BrandColor
Accept pipeline input: False
Accept wildcard characters: False
```

### -ComputerManufacturer
Temporary Parameter

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 3
Default value: (Get-MyComputerManufacturer -Brief)
Accept pipeline input: False
Accept wildcard characters: False
```

### -ComputerProduct
Temporary Parameter

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 4
Default value: (Get-MyComputerProduct)
Accept pipeline input: False
Accept wildcard characters: False
```

### -v2
{{ Fill v2 Description }}

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

## NOTES
25.1.17 Added a temporary parameter v2 to filter DriverPacks by Manufacturer

## RELATED LINKS
