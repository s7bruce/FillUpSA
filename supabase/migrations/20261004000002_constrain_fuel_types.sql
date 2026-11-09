delete from public.fuel_price_history
where fuel_type not in ('E10', '91', '95', '98', 'Diesel', 'LPG');

alter table public.fuel_price_history
    add constraint fuel_price_history_supported_fuel_type
    check (fuel_type in ('E10', '91', '95', '98', 'Diesel', 'LPG'));

