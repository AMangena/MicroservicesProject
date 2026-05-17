using Microsoft.EntityFrameworkCore;
using Shared.Models;

var builder = WebApplication.CreateBuilder(args);

// Azure SQL with Retry Logic
builder.Services.AddDbContext<ProductDbContext>(options =>
    options.UseSqlServer(
        builder.Configuration.GetConnectionString("DefaultConnection"),
        sqlOptions =>
        {
            sqlOptions.EnableRetryOnFailure(
                maxRetryCount: 5,
                maxRetryDelay: TimeSpan.FromSeconds(30),
                errorNumbersToAdd: null);
        }));

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();

// ==================== AUTO CREATE DATABASE ====================
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<ProductDbContext>();
    try
    {
        db.Database.EnsureCreated();
        Console.WriteLine("✅ ProductDb initialized successfully on Azure SQL!");
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

app.MapGet("/products", async (ProductDbContext db) => await db.Products.ToListAsync());
app.MapGet("/products/{id}", async (int id, ProductDbContext db) => await db.Products.FindAsync(id));

app.MapPost("/products", async (Product product, ProductDbContext db) =>
{
    db.Products.Add(product);
    await db.SaveChangesAsync();
    return Results.Created($"/products/{product.Id}", product);
});

app.Run();

public class ProductDbContext : DbContext
{
    public ProductDbContext(DbContextOptions<ProductDbContext> options) : base(options) { }
    public DbSet<Product> Products => Set<Product>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Product>()
            .Property(p => p.Price)
            .HasPrecision(18, 2);
    }
}