using Microsoft.EntityFrameworkCore;
using Shared.Models;

var builder = Host.CreateApplicationBuilder(args);

// Azure SQL with Retry Logic
builder.Services.AddDbContext<PaymentDbContext>(options =>
    options.UseSqlServer(
        builder.Configuration.GetConnectionString("DefaultConnection"),
        sqlOptions =>
        {
            sqlOptions.EnableRetryOnFailure(
                maxRetryCount: 5,
                maxRetryDelay: TimeSpan.FromSeconds(30),
                errorNumbersToAdd: null);
        }));

builder.Services.AddHostedService<PaymentWorker>();

var host = builder.Build();

// Auto-create database
using (var scope = host.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<PaymentDbContext>();
    try
    {
        db.Database.EnsureCreated();
        Console.WriteLine("✅ PaymentDb initialized successfully on Azure SQL!");
    }
    catch (Exception ex)
    {
        Console.WriteLine($"⚠️ Could not connect to database at startup: {ex.Message}");
        Console.WriteLine("   Service will still start — fix firewall/connection string and restart.");
    }
}

host.Run();

public class PaymentDbContext : DbContext
{
    public PaymentDbContext(DbContextOptions<PaymentDbContext> options) : base(options) { }
    public DbSet<PaymentRecord> Payments => Set<PaymentRecord>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<PaymentRecord>()
            .Property(p => p.Amount)
            .HasPrecision(18, 2);
    }
}

public class PaymentRecord
{
    public int Id { get; set; }
    public int OrderId { get; set; }
    public decimal Amount { get; set; }
    public string Status { get; set; } = "Completed";
    public DateTime ProcessedAt { get; set; } = DateTime.UtcNow;
}

public class PaymentWorker : BackgroundService
{
    private readonly ILogger<PaymentWorker> _logger;
    public PaymentWorker(ILogger<PaymentWorker> logger) => _logger = logger;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            _logger.LogInformation("💰 Payment Service is running at {time}", DateTime.UtcNow);
            await Task.Delay(15000, stoppingToken);
        }
    }
}