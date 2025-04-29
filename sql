-- Tworzenie tabeli ustawień użytkownika
CREATE TABLE user_settings (
    username NVARCHAR(100) PRIMARY KEY,
    theme NVARCHAR(50),
    font_family NVARCHAR(100),
    font_size INT,
    last_update DATETIME DEFAULT GETDATE()
);

-- Indeks na kolumnie username (chociaż jako klucz główny już ma indeks)
CREATE INDEX idx_user_settings_username ON user_settings(username);


-- Procedura do zapisywania ustawień użytkownika
CREATE OR ALTER PROCEDURE SaveUserSettings
    @username NVARCHAR(100),
    @theme NVARCHAR(50),
    @font_family NVARCHAR(100),
    @font_size INT
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Wstaw lub zaktualizuj ustawienia
    MERGE user_settings AS target
    USING (SELECT @username AS username, @theme AS theme, 
           @font_family AS font_family, @font_size AS font_size) AS source
    ON (target.username = source.username)
    WHEN MATCHED THEN
        UPDATE SET 
            theme = source.theme,
            font_family = source.font_family,
            font_size = source.font_size,
            last_update = GETDATE()
    WHEN NOT MATCHED THEN
        INSERT (username, theme, font_family, font_size, last_update)
        VALUES (source.username, source.theme, source.font_family, source.font_size, GETDATE());
END;
GO

-- Procedura do pobierania ustawień użytkownika
CREATE OR ALTER PROCEDURE GetUserSettings
    @username NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Pobierz ustawienia dla podanego użytkownika
    SELECT theme, font_family, font_size
    FROM user_settings
    WHERE username = @username;
END;
GO


-- Utwórz funkcję tabelaryczną do efektywnego filtrowania danych grafiku
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[fn_GetScheduleData]') AND type in (N'FN', N'IF', N'TF', N'FS', N'FT'))
    DROP FUNCTION [dbo].[fn_GetScheduleData]
GO

CREATE FUNCTION [dbo].[fn_GetScheduleData]
(
    @Year INT,
    @Month INT,
    @Wydzial NVARCHAR(MAX) = NULL,
    @Przelozony NVARCHAR(MAX) = NULL,
    @Uzytkownik NVARCHAR(MAX) = NULL
)
RETURNS TABLE
AS
RETURN
(
    SELECT 
        k.WydzialGrafik, 
        k.PrzelozonyDane, 
        k.UzytkownikDane, 
        k.Uzytkownik,
        CONVERT(VARCHAR(10), g.Data, 120) AS Data, 
        g.Symbol,
        DATEDIFF(hour, g.DataOd, g.DataDo) AS godziny_pracy, 
        g.Id,
        CASE WHEN s.Id IS NOT NULL THEN 1 ELSE 0 END AS Spotkania,
        CASE WHEN sz.Id IS NOT NULL THEN 1 ELSE 0 END AS Szkolenia,
        CASE WHEN n.Id IS NOT NULL THEN 1 ELSE 0 END AS Nadgodziny,
        DATEPART(HOUR,g.DataOd) start_hour 
    FROM 
        p_v_zz_GrafikiPracy g
    JOIN 
        p_t_do_KonfiguracjaZatrudnienie k ON k.Uzytkownik = g.Uzytkownik 
                                      AND k.Rok = g.Rok 
                                      AND k.Miesiac = g.Miesiac
    LEFT JOIN 
        (SELECT DISTINCT Uzytkownik, Data, MIN(Id) AS Id 
         FROM [dbo].[p_v_zz_Spotkania] 
         WHERE Rok = @Year AND Miesiac = @Month AND Status = 1
         GROUP BY Uzytkownik, Data) s ON g.Uzytkownik = s.Uzytkownik AND g.Data = s.Data
    LEFT JOIN 
        (SELECT DISTINCT Uzytkownik, Data, MIN(Id) AS Id 
         FROM [dbo].[p_v_zz_Szkolenia] 
         WHERE Rok = @Year AND Miesiac = @Month AND Status = 1
         GROUP BY Uzytkownik, Data) sz ON g.Uzytkownik = sz.Uzytkownik AND g.Data = sz.Data
    LEFT JOIN 
        (SELECT DISTINCT Uzytkownik, Data, MIN(Id) AS Id 
         FROM [dbo].[p_T_ZZ_Nadgodziny] 
         WHERE Rok = @Year AND Miesiac = @Month
         GROUP BY Uzytkownik, Data) n ON g.Uzytkownik = n.Uzytkownik AND g.Data = n.Data
    WHERE 
        g.Rok = @Year AND g.Miesiac = @Month 
        AND k.Flaga = 1
        AND (@Wydzial IS NULL OR k.WydzialGrafik = @Wydzial)
        AND (@Przelozony IS NULL OR k.PrzelozonyDane = @Przelozony)
        AND (@Uzytkownik IS NULL OR k.Uzytkownik = @Uzytkownik)
);
GO

-- Utwórz funkcję tabelaryczną do efektywnego pobierania zdarzeń
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[fn_GetEventsData]') AND type in (N'FN', N'IF', N'TF', N'FS', N'FT'))
    DROP FUNCTION [dbo].[fn_GetEventsData]
GO

CREATE FUNCTION [dbo].[fn_GetEventsData]
(
    @Year INT,
    @Month INT
)
RETURNS TABLE
AS
RETURN
(
    -- Spotkania
    SELECT 'Spotkanie' AS EventType, 
           Id, Temat, Nazwa, Uzytkownik, Data, DataOd, DataDo, StatusNazwa
    FROM p_v_zz_Spotkania
    WHERE Rok = @Year AND Miesiac = @Month AND Status = 1
    
    UNION ALL
    
    -- Szkolenia
    SELECT 'Szkolenie' AS EventType,
           Id, Temat, Nazwa, Uzytkownik, Data, DataOd, DataDo, StatusNazwa
    FROM p_v_zz_Szkolenia
    WHERE Rok = @Year AND Miesiac = @Month AND Status = 1
    
    UNION ALL
    
    -- Nadgodziny
    SELECT 'Nadgodziny' AS EventType,
           Id, 'Nadgodziny' AS Temat, 'Nadgodziny' AS Nazwa, 
           Uzytkownik, Data, DataOd, DataDo, 'Wstawione' AS StatusNazwa
    FROM p_t_zz_Nadgodziny
    WHERE Rok = @Year AND Miesiac = @Month AND [StatusRozliczenia] = 1
);
GO
