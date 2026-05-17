using Microsoft.EntityFrameworkCore;
using Shared.Models;
using Polly;
using Polly.Extensions.Http;
using System.Net;

var builder = WebApplication.CreateBuilder(args);

// ====================== Azure SQL with Retry ======================
builder.Services.AddDbContext<OrderDbContext>(options =>
    options.UseSqlServer(
        builder.Configuration.GetConnectionString("DefaultConnection"),
        sqlOptions =>
        {
            sqlOptions.EnableRetryOnFailure(
                maxRetryCount: 5,
                maxRetryDelay: TimeSpan.FromSeconds(30),
                errorNumbersToAdd: null);
        }));

// ====================== Polly HttpClient with Retry ======================
builder.Services.AddHttpClient("ProductApiClient", client =>
{
    client.BaseAddress = new Uri("http://product-api:8080");
    client.Timeout = TimeSpan.FromSeconds(15);
})
.AddPolicyHandler(GetRetryPolicy());   // Polly Retry Policy

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();

// ==================== AUTO CREATE DATABASE ====================
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<OrderDbContext>();
    try
    {
        db.Database.EnsureCreated();
        Console.WriteLine("✅ OrderDb initialized successfully on Azure SQL!");
    }
    catch (Exception ex)
    {
        Console.WriteLine($"⚠️ Could not connect to database at startup: {ex.Message}");
        Console.WriteLine("   API will still start — fix firewall/connection string and restart.");
    }
}
// ============================================================

app.UseSwagger();
app.UseSwaggerUI();

app.MapPost("/orders", async (CreateOrderRequest req, OrderDbContext db, IHttpClientFactory httpClientFactory) =>
{
    var httpClient = httpClientFactory.CreateClient("ProductApiClient");

    var product = await httpClient.GetFromJsonAsync<Product>($"/products/{req.ProductId}");

    if (product == null)
        return Results.NotFound($"Product with ID {req.ProductId} not found");

    if (product.Stock < req.Quantity)
        return Results.BadRequest("Insufficient stock");

    var order = new Order
    {
        CustomerId = req.CustomerId,
        CustomerEmail = req.CustomerEmail,
        Items = [new OrderItem { ProductId = product.Id, Quantity = req.Quantity, UnitPrice = product.Price }],
        TotalAmount = product.Price * req.Quantity,
        Status = "Pending",
        OrderDate = DateTime.UtcNow
    };

    db.Orders.Add(order);
    await db.SaveChangesAsync();

    Console.WriteLine($"✅ Order {order.Id} created successfully!");
    return Results.Created($"/orders/{order.Id}", order);
});

app.Run();

// ====================== Polly Retry Policy ======================
static IAsyncPolicy<HttpResponseMessage> GetRetryPolicy()
{
    return HttpPolicyExtensions
        .HandleTransientHttpError()           // Handles 5xx and network failures
        .OrResult(msg => msg.StatusCode == HttpStatusCode.NotFound)
        .WaitAndRetryAsync(
            retryCount: 3,
            sleepDurationProvider: retryAttempt => TimeSpan.FromSeconds(Math.Pow(2, retryAttempt)), // Exponential backoff
            onRetry: (outcome, timespan, retryAttempt, context) =>
            {
                Console.WriteLine($"⚠️ Retry {retryAttempt} for Product API after {timespan.TotalSeconds}s");
            });
}

// ====================== DbContext & Record ======================
public class OrderDbContext : DbContext
{
    public OrderDbContext(DbContextOptions<OrderDbContext> options) : base(options) { }
    public DbSet<Order> Orders => Set<Order>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Order>(order =>
        {
            order.Property(o => o.TotalAmount).HasPrecision(18, 2);

            order.OwnsMany(o => o.Items, item =>
            {
                item.WithOwner().HasForeignKey("OrderId");
                item.Property<int>("Id");
                item.HasKey("Id");
                item.Property(i => i.UnitPrice).HasPrecision(18, 2);
            });
        });
    }
}

public record CreateOrderRequest(
    int CustomerId,
    string CustomerEmail,
    int ProductId,
    int Quantity
);