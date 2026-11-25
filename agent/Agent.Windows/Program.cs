using Agent.Core;
using Agent.Windows;

return await AgentHost.RunAsync(new WindowsInputInjector(), new WindowsPermissionChecker());
