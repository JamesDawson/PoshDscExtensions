PoshDscExtensions
=================

This is a sandbox for my experiments with creating custom resource provider modules for PowerShell v4 Desired State Configuration.

### Installation Instructions ###

To use one of the modules listed below simply copy the folder containing the module you're interested in to:

    C:\Windows\System32\WindowsPowerShell\v1.0\Modules\PSDesiredStateConfiguration\PSProviders

### Module List ###

- **Timezone** - sets the system timezone (my first, and very basic, custom resource)
- **Chocolatey** - a basic wrapper around [Chocolatey](http://chocolatey.org) to support installing it and adding/removing its packages
- **AzureVm** - provision Azure VM roles using DSC
- **AzurePublishingProfile** - generates and installs an Azure publishing profile to allow other Azure-related resources access to the specified subscription
- **AzureAffinityGroup** - manage Azure affinity groups using DSC
- **AzureNetwork** - provides basic management of Azure virtual networks

