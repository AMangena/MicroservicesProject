using Microsoft.EntityFrameworkCore;
using Shared.Models;

var builder = Host.CreateApplicationBuilder(args);

// Azure SQL with Retry Logic
builder.Services.AddDbContext<NotificationDbContext>(options =>
    options.UseSqlServer(
        builder.Configuration.GetConnectionString("DefaultConnection"),
        sqlOptions =>
        {
            sqlOptions.EnableRetryOnFailure(
                maxRetryCount: 5,
                maxRetryDelay: TimeSpan.FromSeconds(30),
                errorNumbersToAdd: null);
        }));

builder.Services.AddHostedService<NotificationWorker>();

var host = builder.Build();

// Auto-create database
using (var scope = host.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<NotificationDbContext>();
    try
    {
        db.Database.EnsureCreated();
        Console.WriteLine("✅ NotificationDb initialized successfully on Azure SQL!");
    }
    catch (Exception ex)
    {
        Console.WriteLine($"⚠️ Could not connect to database at startup: {ex.Message}");
        Console.WriteLine("   Service will still start — fix firewall/connection string and restart.");
    }
}

host.Run();

public class NotificationDbContext : DbContext
{
    public NotificationDbContext(DbContextOptions<NotificationDbContext> options) : base(options) { }
    public DbSet<NotificationRecord> Notifications => Set<NotificationRecord>();
}

public class NotificationRecord
{
    public int Id { get; set; }
    public int OrderId { get; set; }
    public string ToEmail { get; set; } = string.Empty;
    public string Type { get; set; } = string.Empty;
    public string Message { get; set; } = string.Empty;
    public DateTime SentAt { get; set; } = DateTime.UtcNow;
}

public class NotificationWorker : BackgroundService
{
    private readonly ILogger<NotificationWorker> _logger;
    public NotificationWorker(ILogger<NotificationWorker> logger) => _logger = logger;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            _logger.LogInformation("📧 Notification Service is running at {time}", DateTime.UtcNow);
            await Task.Delay(20000, stoppingToken);
        }
    }
}