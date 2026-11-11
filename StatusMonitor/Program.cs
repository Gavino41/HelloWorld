using StatusMonitor;

var builder = Host.CreateApplicationBuilder(args);

builder.Services.AddWindowsService(options =>
{
    options.ServiceName = "HelloWorldStatusMonitor";
});
builder.Services.AddHostedService<Worker>();

var host = builder.Build();
host.Run();