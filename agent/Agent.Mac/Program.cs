using Agent.Core;
using Agent.Mac;

return await AgentHost.RunAsync(new MacInputInjector(), new MacPermissionChecker());
