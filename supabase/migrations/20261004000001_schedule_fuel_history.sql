create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

select cron.schedule(
    'collect-fuel-history-every-30-minutes',
    '*/30 * * * *',
    $schedule$
    select net.http_post(
        url := 'https://febmlfvosczhcbcccjxm.supabase.co/functions/v1/collect-fuel-history',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'apikey', 'sb_publishable_twrstyGVk7ZufVs6xBljzg_r0CJ2_dv',
            'Authorization', 'Bearer sb_publishable_twrstyGVk7ZufVs6xBljzg_r0CJ2_dv'
        ),
        body := '{}'::jsonb
    );
    $schedule$
);
