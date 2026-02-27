using Prometheus;
using System.Security.Cryptography;
using System.Text;
using Yarp.ReverseProxy.SessionAffinity;
using Yarp.ReverseProxy.Transforms;

var builder = WebApplication.CreateBuilder(args);

var proxySettings = builder.Configuration.GetSection("Proxy").Get<ProxySettings>() ?? new ProxySettings();

builder.Services.AddSingleton<ISessionAffinityPolicy, McpSessionAffinityPolicy>();

builder.Services
	.AddReverseProxy()
	.LoadFromConfig(builder.Configuration.GetSection("ReverseProxy"))
	.AddTransforms(context =>
	{
		context.AddRequestTransform(transformContext =>
		{
			transformContext.ProxyRequest.Headers.Remove(proxySettings.ApiKeyHeader);
			return ValueTask.CompletedTask;
		});
	});

builder.Services.AddHealthChecks();

builder.Services.ConfigureHttpClientDefaults(http =>
{
	http.ConfigurePrimaryHttpMessageHandler(() => new SocketsHttpHandler
	{
		AllowAutoRedirect = false,
		UseCookies = false
	});

	http.ConfigureHttpClient(client =>
	{
		client.Timeout = TimeSpan.FromMinutes(proxySettings.UpstreamTimeoutMinutes);
	});
});

var app = builder.Build();

app.MapHealthChecks("/healthz");
app.MapMetrics();
app.UseWhen(
	ctx => !ctx.Request.Path.StartsWithSegments("/healthz") &&
	       !ctx.Request.Path.StartsWithSegments("/metrics"),
	branch => branch.UseHttpMetrics()
);

app.MapGet("/", () => Results.Ok(new
{
	service = "mcp-yarp-proxy",
	status = "ok"
}));

app.Use(async (context, next) =>
{
	if (!context.Request.Path.StartsWithSegments("/mcp", StringComparison.OrdinalIgnoreCase))
	{
		await next();
		return;
	}

	if (string.IsNullOrWhiteSpace(proxySettings.ApiKey))
	{
		context.Response.StatusCode = StatusCodes.Status500InternalServerError;
		await context.Response.WriteAsync("Proxy API key is not configured.");
		return;
	}

	if (!context.Request.Headers.TryGetValue(proxySettings.ApiKeyHeader, out var incomingKey))
	{
		context.Response.StatusCode = StatusCodes.Status401Unauthorized;
		await context.Response.WriteAsync("Missing API key.");
		return;
	}

	if (!FixedTimeEquals(incomingKey.ToString(), proxySettings.ApiKey))
	{
		context.Response.StatusCode = StatusCodes.Status401Unauthorized;
		await context.Response.WriteAsync("Invalid API key.");
		return;
	}

	await next();
});

app.MapReverseProxy();

app.Run();

static bool FixedTimeEquals(string left, string right)
{
	var leftBytes = Encoding.UTF8.GetBytes(left);
	var rightBytes = Encoding.UTF8.GetBytes(right);
	return CryptographicOperations.FixedTimeEquals(leftBytes, rightBytes);
}

internal sealed class ProxySettings
{
	// Agent Service injects credentials from an ApiKey connection using the 'api-key' header.
	public string ApiKeyHeader { get; set; } = "api-key";
	public string ApiKey { get; set; } = string.Empty;
	public int UpstreamTimeoutMinutes { get; set; } = 10;
}
