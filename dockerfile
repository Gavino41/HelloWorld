FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY web/HelloWorld.csproj web/
RUN dotnet restore web/HelloWorld.csproj
COPY web/ web/
RUN dotnet publish web/HelloWorld.csproj -c Release -o /app/publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app
COPY --from=build /app/publish .
USER $APP_UID
EXPOSE 8080
ENTRYPOINT ["dotnet", "HelloWorld.dll"]