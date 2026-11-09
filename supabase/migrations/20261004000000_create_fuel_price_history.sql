create table if not exists public.fuel_price_history (
    captured_at timestamptz not null,
    fuel_type text not null,
    low numeric(6, 1) not null,
    high numeric(6, 1) not null,
    average numeric(6, 1) not null,
    station_count integer not null check (station_count > 0),
    primary key (captured_at, fuel_type)
);

create index if not exists fuel_price_history_fuel_date_idx
    on public.fuel_price_history (fuel_type, captured_at desc);

alter table public.fuel_price_history enable row level security;

create policy "Public can read aggregate fuel history"
    on public.fuel_price_history
    for select
    to anon, authenticated
    using (true);

revoke insert, update, delete on public.fuel_price_history from anon, authenticated;

