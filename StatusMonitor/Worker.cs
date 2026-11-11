namespace StatusMonitor;

public class Worker(ILogger<Worker> logger, IHostApplicationLifetime lifetime, IConfiguration config) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var url      = config["Monitor:Url"] ?? "http://localhost/HelloWorldApp/";
        var interval = config.GetValue<int>("Monitor:IntervalSeconds", 60);
        var timeout  = config.GetValue<int>("Monitor:TimeoutSeconds", 10);

        using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(timeout) };
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(interval));
        var logPath = Path.Combine(AppContext.BaseDirectory, "status.log");

        do
        {
            bool isOk;
            string result;

            try
            {
                using var response = await http.GetAsync(url, stoppingToken);
                isOk = (int)response.StatusCode == 200;
                result = $"{(int)response.StatusCode} {response.ReasonPhrase}";
            }
            catch (HttpRequestException ex)
            {
                isOk = false;
                result = $"ERROR {ex.Message}";
            }
            catch (OperationCanceledException) when (!stoppingToken.IsCancellationRequested)
            {
                isOk = false;
                result = "ERROR request timed out";
            }

            logger.LogInformation("{Result}", result);
            await File.AppendAllTextAsync(
                logPath,
                $"{DateTime.Now:s} | {result}{Environment.NewLine}",
                stoppingToken);

            if (!isOk)
            {
                Environment.ExitCode = 1;
                lifetime.StopApplication();
                return;
            }
        }
        while (await timer.WaitForNextTickAsync(stoppingToken));
    }
}